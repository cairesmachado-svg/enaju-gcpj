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
                                     max_results = 3000, rows_per_call = 1000) {

  cat("\n--- Coletando Corpus", corpus_id, "via Crossref ---\n")

  out_dir <- here::here("data", "raw", paste0("corpus_", corpus_id))
  out_rds <- file.path(out_dir, paste0("crossref_raw_", corpus_id, ".rds"))

  if (file.exists(out_rds)) {
    cat("[CACHE] Crossref Corpus", corpus_id, "já coletado.\n")
    return(readRDS(out_rds))
  }

  # Coleta em lotes com cursor
  all_items <- list()
  offset    <- 0
  collected <- 0

  repeat {
    to_fetch  <- min(rows_per_call, max_results - collected)
    if (to_fetch <= 0) break

    resp <- tryCatch({
      rcrossref::cr_works(
        query   = query_str,
        limit   = to_fetch,
        offset  = offset,
        filter  = c(
          type    = "journal-article",
          from_pub_date = "1995-01-01"
        ),
        select  = c(
          "DOI", "title", "author", "published-print", "published-online",
          "container-title", "volume", "issue", "page",
          "is-referenced-by-count", "subject", "abstract",
          "ISSN", "publisher", "type", "language"
        ),
        .progress = FALSE
      )
    }, error = function(e) {
      cat("[AVISO] Crossref erro no offset", offset, ":", conditionMessage(e), "\n")
      Sys.sleep(5)
      NULL
    })

    if (is.null(resp) || is.null(resp$data) || nrow(resp$data) == 0) break

    all_items[[length(all_items) + 1]] <- resp$data
    collected <- collected + nrow(resp$data)
    offset    <- offset + nrow(resp$data)

    cat(sprintf("  Coletados: %d / %d\n", collected, max_results))

    if (nrow(resp$data) < to_fetch) break
    Sys.sleep(1)
  }

  if (length(all_items) == 0) {
    cat("[AVISO] Nenhum resultado Crossref para corpus", corpus_id, "\n")
    return(NULL)
  }

  df <- dplyr::bind_rows(all_items)

  # Normalizar colunas
  df <- df %>%
    dplyr::mutate(
      source_db  = "Crossref",
      corpus_id  = corpus_id,
      query_date = Sys.Date(),
      title      = purrr::map_chr(title, ~if (length(.x) > 0) .x[[1]] else NA_character_),
      journal    = purrr::map_chr(`container-title`,
                                  ~if (!is.null(.x) && length(.x) > 0) .x[[1]] else NA_character_),
      year       = dplyr::coalesce(
        as.integer(stringr::str_extract(`published.print`, "\\d{4}")),
        as.integer(stringr::str_extract(`published.online`, "\\d{4}"))
      ),
      doi_clean  = DOI,
      first_author = purrr::map_chr(author, function(a) {
        if (is.data.frame(a) && nrow(a) > 0) {
          paste(
            a$family[1] %||% "",
            a$given[1] %||% ""
          ) %>% trimws()
        } else NA_character_
      }),
      citations  = `is-referenced-by-count`
    ) %>%
    dplyr::select(
      doi_clean, title, year, journal, first_author,
      citations, subject, publisher, source_db, corpus_id, query_date
    ) %>%
    dplyr::distinct(doi_clean, .keep_all = TRUE)

  saveRDS(df, out_rds)
  readr::write_csv(df, file.path(out_dir, paste0("crossref_raw_", corpus_id, ".csv")))

  cat("[OK] Crossref Corpus", corpus_id, ":", nrow(df), "registros salvos\n")
  log_step(paste("Crossref Corpus", corpus_id, ":", nrow(df), "registros"), "04_collect_crossref")
  return(df)
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

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
