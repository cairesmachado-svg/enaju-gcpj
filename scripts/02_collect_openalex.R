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
                                     per_page = 200, max_results = 10000) {

  cat("\n--- Coletando Corpus", corpus_id, "via OpenAlex ---\n")

  out_dir <- here::here("data", "raw", paste0("corpus_", corpus_id))
  out_rds <- file.path(out_dir, paste0("openalex_raw_", corpus_id, ".rds"))
  out_csv <- file.path(out_dir, paste0("openalex_raw_", corpus_id, ".csv"))

  if (file.exists(out_rds)) {
    cat("[CACHE] Corpus", corpus_id, "OpenAlex já coletado.\n")
    return(readRDS(out_rds))
  }

  # Usar oa_fetch para busca por texto livre
  result <- tryCatch({
    openalexR::oa_fetch(
      entity        = "works",
      search        = search_terms,
      per_page      = per_page,
      count_only    = FALSE,
      verbose       = TRUE,
      options       = list(select = paste(
        "id,doi,title,display_name,publication_year,publication_date",
        "type,cited_by_count,authorships,primary_location",
        "open_access,concepts,keywords,abstract_inverted_index",
        "referenced_works_count,counts_by_year",
        sep = ","
      ))
    )
  }, error = function(e) {
    cat("[ERRO] OpenAlex falhou para corpus", corpus_id, ":", conditionMessage(e), "\n")
    NULL
  })

  if (is.null(result) || nrow(result) == 0) {
    cat("[AVISO] Sem resultados OpenAlex para corpus", corpus_id, "\n")
    return(NULL)
  }

  # Limitar ao máximo definido
  if (nrow(result) > max_results) result <- result[1:max_results, ]

  # Extrair campos planos
  df <- result %>%
    dplyr::mutate(
      source_db  = "OpenAlex",
      corpus_id  = corpus_id,
      query_date = Sys.Date(),
      # Extrair DOI limpo
      doi_clean  = dplyr::if_else(
        !is.na(doi),
        stringr::str_remove(doi, "https://doi.org/"),
        NA_character_
      ),
      # Extrair primeiros autores
      first_author = purrr::map_chr(authorships, function(a) {
        if (is.data.frame(a) && nrow(a) > 0 && "author" %in% names(a)) {
          tryCatch(a$author[[1]]$display_name[1], error = function(e) NA_character_)
        } else NA_character_
      }),
      # Journal/fonte
      journal = purrr::map_chr(primary_location, function(loc) {
        if (is.list(loc) && !is.null(loc$source)) {
          tryCatch(loc$source$display_name, error = function(e) NA_character_)
        } else NA_character_
      }),
      # Country
      country_first_author = purrr::map_chr(authorships, function(a) {
        if (is.data.frame(a) && nrow(a) > 0 && "institutions" %in% names(a)) {
          inst <- a$institutions[[1]]
          if (is.data.frame(inst) && "country_code" %in% names(inst))
            tryCatch(inst$country_code[1], error = function(e) NA_character_)
          else NA_character_
        } else NA_character_
      })
    ) %>%
    dplyr::select(
      id, doi_clean, title = display_name, year = publication_year,
      type, cited_by_count, first_author, journal, country_first_author,
      open_access, source_db, corpus_id, query_date
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
for (corp in c("A", "B", "C", "D")) {
  Sys.sleep(1)
  results_oa[[corp]] <- collect_openalex_corpus(
    corpus_id    = corp,
    search_terms = QUERIES[[corp]]$openalex,
    per_page     = 200,
    max_results  = 10000
  )
}

cat("\n=== Sumário OpenAlex ===\n")
for (corp in c("A", "B", "C", "D")) {
  n <- if (!is.null(results_oa[[corp]])) nrow(results_oa[[corp]]) else 0
  cat(sprintf("  Corpus %s: %d registros\n", corp, n))
}

log_step("Coleta OpenAlex concluída", "02_collect_openalex")
cat("\nPróximo passo: execute 03_collect_semantic_scholar.R\n")
