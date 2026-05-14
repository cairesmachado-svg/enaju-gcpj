# =============================================================================
# 02_collect_openalex.R
# Coleta via OpenAlex API (acesso aberto, sem limite de registros)
# Dependência: 00_setup.R executado previamente
# Saída: data/raw/corpus_{A,B,C,D}/openalex_*.rds
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando coleta OpenAlex", "02_collect_openalex")

library(openalexR)
library(dplyr)
library(progress)

QUERIES <- readRDS(here::here("data", "processed", "queries.rds"))

# Configurar email para polite pool
oa_email <- Sys.getenv("OPENALEX_EMAIL")
if (nchar(oa_email) > 0) options(openalexR.mailto = oa_email)

# -----------------------------------------------------------------------------
# Função de coleta OpenAlex com paginação automática
# -----------------------------------------------------------------------------

collect_openalex_corpus <- function(corpus_id, search_terms,
                                     per_page = 200,
                                     max_results = as.integer(
                                       Sys.getenv("ENAJU_OPENALEX_MAX",
                                                  unset = "5000"))) {

  cat("\n--- Coletando Corpus", corpus_id, "via OpenAlex ---\n")

  out_dir <- here::here("data", "raw", paste0("corpus_", corpus_id))
  out_rds <- file.path(out_dir, paste0("openalex_raw_", corpus_id, ".rds"))
  out_csv <- file.path(out_dir, paste0("openalex_raw_", corpus_id, ".csv"))

  if (file.exists(out_rds)) {
    cat("[CACHE] Corpus", corpus_id, "OpenAlex já coletado.\n")
    return(readRDS(out_rds))
  }

  # Usar oa_fetch para busca por texto livre.
  # OBS: openalexR aceita 'search' como string e respeita a sintaxe OR/AND nativa.
  # Restringimos por publication_year para o recorte 1995-2025.
  # Limitamos número de páginas para respeitar max_results — oa_fetch baixa
  # tudo se 'pages' não for especificado, o que pode ser muito custoso.
  pages_needed <- max(1L, ceiling(max_results / per_page))
  result <- tryCatch({
    openalexR::oa_fetch(
      entity            = "works",
      search            = search_terms,
      from_publication_date = "1995-01-01",
      to_publication_date   = "2025-12-31",
      per_page          = per_page,
      pages             = seq_len(pages_needed),
      count_only        = FALSE,
      verbose           = TRUE
    )
  }, error = function(e) {
    cat("[ERRO] OpenAlex falhou para corpus", corpus_id, ":", conditionMessage(e), "\n")
    NULL
  })

  if (is.null(result) || nrow(result) == 0) {
    cat("[AVISO] Sem resultados OpenAlex para corpus", corpus_id, "\n")
    return(NULL)
  }

  # Garantia adicional: limitar ao máximo definido (caso oa_fetch retorne além).
  if (nrow(result) > max_results) result <- result[seq_len(max_results), ]

  # Extrair campos planos.
  # openalexR retorna nomes diferentes conforme versão: 'doi' ou 'id' (URL OpenAlex);
  # 'display_name' como título; 'authorships' como list-col aninhada.
  # Aplicamos defesas para variações de schema.
  has_col <- function(d, col) col %in% names(d)

  # openalexR (>= 2.x) achata authorships em uma tibble por linha com colunas:
  # id, display_name, orcid, author_position, affiliations (list-col), affiliation_raw
  safe_first_author <- function(a) {
    if (is.null(a)) return(NA_character_)
    if (is.data.frame(a) && nrow(a) > 0) {
      if ("display_name" %in% names(a)) return(as.character(a$display_name[1]))
      if ("au_display_name" %in% names(a)) return(as.character(a$au_display_name[1]))
      if ("author" %in% names(a)) {
        au <- a$author[[1]]
        if (is.list(au) && !is.null(au$display_name)) return(as.character(au$display_name))
      }
    }
    NA_character_
  }

  safe_country <- function(a) {
    if (is.null(a)) return(NA_character_)
    if (is.data.frame(a) && nrow(a) > 0) {
      # Versão atual: 'affiliations' é uma list-col com tibble por autor;
      # cada tibble pode ter colunas country_code / institution_id.
      if ("affiliations" %in% names(a)) {
        aff <- a$affiliations[[1]]
        if (is.data.frame(aff) && "country_code" %in% names(aff))
          return(as.character(aff$country_code[1]))
      }
      # Versão antiga: 'institutions'
      if ("institutions" %in% names(a)) {
        inst <- a$institutions[[1]]
        if (is.data.frame(inst) && "country_code" %in% names(inst))
          return(as.character(inst$country_code[1]))
      }
    }
    NA_character_
  }

  safe_journal <- function(loc) {
    if (is.null(loc)) return(NA_character_)
    if (is.list(loc) && !is.null(loc$source)) {
      src <- loc$source
      if (is.list(src) && !is.null(src$display_name)) return(as.character(src$display_name))
    }
    NA_character_
  }

  doi_col   <- if (has_col(result, "doi")) result$doi else rep(NA_character_, nrow(result))
  title_col <- if (has_col(result, "display_name")) result$display_name
               else if (has_col(result, "title")) result$title
               else rep(NA_character_, nrow(result))
  year_col  <- if (has_col(result, "publication_year")) result$publication_year else NA_integer_
  type_col  <- if (has_col(result, "type")) result$type else NA_character_
  cit_col   <- if (has_col(result, "cited_by_count")) result$cited_by_count else NA_integer_
  oa_col    <- if (has_col(result, "open_access")) result$open_access else NA
  id_col    <- if (has_col(result, "id")) result$id else seq_len(nrow(result))

  first_author_v <- if (has_col(result, "authorships"))
    purrr::map_chr(result$authorships, safe_first_author) else NA_character_
  country_v <- if (has_col(result, "authorships"))
    purrr::map_chr(result$authorships, safe_country) else NA_character_
  journal_v <- if (has_col(result, "source_display_name")) result$source_display_name
               else if (has_col(result, "primary_location"))
                 purrr::map_chr(result$primary_location, safe_journal)
               else if (has_col(result, "so")) result$so else NA_character_

  df <- tibble::tibble(
    id           = id_col,
    doi_clean    = stringr::str_remove(ifelse(is.na(doi_col), NA_character_, doi_col),
                                       "^https?://doi\\.org/"),
    title        = title_col,
    year         = year_col,
    type         = type_col,
    cited_by_count = cit_col,
    first_author = first_author_v,
    journal      = journal_v,
    country_first_author = country_v,
    open_access  = oa_col,
    source_db    = "OpenAlex",
    corpus_id    = corpus_id,
    query_date   = Sys.Date()
  )

  saveRDS(df, out_rds)
  readr::write_csv(df, out_csv)

  cat("[OK] Corpus", corpus_id, "OpenAlex:", nrow(df), "registros salvos\n")
  log_step(paste("OpenAlex Corpus", corpus_id, ":", nrow(df), "registros"), "02_collect_openalex")
  return(df)
}

# -----------------------------------------------------------------------------
# Executar coleta
# -----------------------------------------------------------------------------

results_oa <- list()
oa_max <- as.integer(Sys.getenv("ENAJU_OPENALEX_MAX", unset = "5000"))
for (corp in c("A", "B", "C", "D")) {
  Sys.sleep(1)
  results_oa[[corp]] <- collect_openalex_corpus(
    corpus_id    = corp,
    search_terms = QUERIES[[corp]]$openalex,
    per_page     = 200,
    max_results  = oa_max
  )
}

cat("\n=== Sumário OpenAlex ===\n")
for (corp in c("A", "B", "C", "D")) {
  n <- if (!is.null(results_oa[[corp]])) nrow(results_oa[[corp]]) else 0
  cat(sprintf("  Corpus %s: %d registros\n", corp, n))
}

log_step("Coleta OpenAlex concluída", "02_collect_openalex")
cat("\nPróximo passo: execute 03_collect_semantic_scholar.R\n")
