# =============================================================================
# 04_collect_crossref.R
# Coleta via Crossref API (rcrossref) para os quatro corpora
# Foco: DOIs, metadados completos, periódicos com fator de impacto documentado
# Dependência: 00_setup.R executado previamente
# Saída: data/raw/corpus_{A,B,C,D}/crossref_*.rds
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando coleta Crossref", "04_collect_crossref")

library(rcrossref)
library(dplyr)
library(progress)

# Operador null-coalesce — definido antes das funções que o utilizam.
`%||%` <- function(a, b) {
  if (is.null(a)) return(b)
  if (length(a) == 0) return(b)
  if (is.atomic(a) && all(is.na(a))) return(b)
  a
}

# Configurar polite pool com email
cr_email <- Sys.getenv("CROSSREF_EMAIL")
if (nchar(cr_email) > 0) {
  options(crossref_email = cr_email)
  cat("[OK] Crossref polite pool configurado:", cr_email, "\n")
}

QUERIES <- readRDS(here::here("data", "processed", "queries.rds"))

# -----------------------------------------------------------------------------
# Função de coleta Crossref com filtros e paginação
# -----------------------------------------------------------------------------

collect_crossref_corpus <- function(corpus_id, query_str,
                                     max_results = as.integer(
                                       Sys.getenv("ENAJU_CROSSREF_MAX", unset = "2000")),
                                     rows_per_call = 1000) {

  cat("\n--- Coletando Corpus", corpus_id, "via Crossref ---\n")

  out_dir <- here::here("data", "raw", paste0("corpus_", corpus_id))
  out_rds <- file.path(out_dir, paste0("crossref_raw_", corpus_id, ".rds"))

  if (file.exists(out_rds)) {
    cat("[CACHE] Crossref Corpus", corpus_id, "já coletado.\n")
    return(readRDS(out_rds))
  }

  # Crossref: usar cursor para paginação profunda (offset não funciona além de 1000).
  # cr_works expõe cursor via argumento `cursor = "*"` e `cursor_max`.
  resp <- tryCatch({
    rcrossref::cr_works(
      query     = query_str,
      filter    = c(
        type          = "journal-article",
        from_pub_date = "1995-01-01"
      ),
      select    = c(
        "DOI", "title", "author", "published-print", "published-online",
        "container-title", "volume", "issue", "page",
        "is-referenced-by-count", "subject",
        "ISSN", "publisher", "type"
      ),
      cursor     = "*",
      cursor_max = max_results,
      limit      = rows_per_call,
      .progress  = "text"
    )
  }, error = function(e) {
    cat("[AVISO] Crossref erro:", conditionMessage(e), "\n")
    NULL
  })

  all_items <- if (!is.null(resp) && !is.null(resp$data) && nrow(resp$data) > 0)
    list(resp$data) else list()

  if (length(all_items) == 0) {
    cat("[AVISO] Nenhum resultado Crossref para corpus", corpus_id, "\n")
    return(NULL)
  }

  df <- dplyr::bind_rows(all_items)

  # Helpers: extrair primeira string de uma célula que pode ser lista/vetor/NA.
  pick_first <- function(x) {
    if (is.null(x)) return(NA_character_)
    if (length(x) == 0) return(NA_character_)
    if (is.list(x)) {
      first <- x[[1]]
      if (is.null(first) || length(first) == 0) return(NA_character_)
      return(as.character(first[1]))
    }
    as.character(x[1])
  }

  col_or_na <- function(d, name) if (name %in% names(d)) d[[name]] else rep(NA, nrow(d))

  pub_print  <- col_or_na(df, "published.print")
  pub_online <- col_or_na(df, "published.online")
  if (is.list(pub_print))  pub_print  <- vapply(pub_print,  pick_first, character(1))
  if (is.list(pub_online)) pub_online <- vapply(pub_online, pick_first, character(1))

  title_v   <- col_or_na(df, "title")
  journal_v <- col_or_na(df, "container.title")
  if (is.list(title_v))   title_v   <- vapply(title_v,   pick_first, character(1))
  if (is.list(journal_v)) journal_v <- vapply(journal_v, pick_first, character(1))

  citations_v <- col_or_na(df, "is.referenced.by.count")
  subject_v   <- col_or_na(df, "subject")
  if (is.list(subject_v)) subject_v <- vapply(subject_v, pick_first, character(1))
  publisher_v <- col_or_na(df, "publisher")
  doi_v       <- col_or_na(df, "doi")
  if (all(is.na(doi_v)) && "DOI" %in% names(df)) doi_v <- df$DOI

  authors_col <- if ("author" %in% names(df)) df$author else replicate(nrow(df), NULL, simplify = FALSE)
  first_author_v <- purrr::map_chr(authors_col, function(a) {
    if (is.data.frame(a) && nrow(a) > 0) {
      fam <- if ("family" %in% names(a)) a$family[1] else ""
      giv <- if ("given"  %in% names(a)) a$given[1]  else ""
      out <- trimws(paste(fam %||% "", giv %||% ""))
      if (nzchar(out)) out else NA_character_
    } else NA_character_
  })

  df <- tibble::tibble(
    doi_clean    = as.character(doi_v),
    title        = title_v,
    year         = dplyr::coalesce(
      suppressWarnings(as.integer(stringr::str_extract(pub_print,  "\\d{4}"))),
      suppressWarnings(as.integer(stringr::str_extract(pub_online, "\\d{4}")))
    ),
    journal      = journal_v,
    first_author = first_author_v,
    citations    = suppressWarnings(as.integer(citations_v)),
    subject      = subject_v,
    publisher    = as.character(publisher_v),
    source_db    = "Crossref",
    corpus_id    = corpus_id,
    query_date   = Sys.Date()
  ) %>%
    dplyr::distinct(doi_clean, .keep_all = TRUE)

  saveRDS(df, out_rds)
  readr::write_csv(df, file.path(out_dir, paste0("crossref_raw_", corpus_id, ".csv")))

  cat("[OK] Crossref Corpus", corpus_id, ":", nrow(df), "registros salvos\n")
  log_step(paste("Crossref Corpus", corpus_id, ":", nrow(df), "registros"), "04_collect_crossref")
  return(df)
}

# Executar
results_cr <- list()
for (corp in c("A", "B", "C", "D")) {
  Sys.sleep(2)
  results_cr[[corp]] <- collect_crossref_corpus(corp, QUERIES[[corp]]$crossref)
}

cat("\n=== Sumário Crossref ===\n")
for (corp in c("A", "B", "C", "D")) {
  n <- if (!is.null(results_cr[[corp]])) nrow(results_cr[[corp]]) else 0
  cat(sprintf("  Corpus %s: %d registros\n", corp, n))
}

log_step("Coleta Crossref concluída", "04_collect_crossref")
cat("\nPróximo passo: execute 05_collect_scielo.R\n")
