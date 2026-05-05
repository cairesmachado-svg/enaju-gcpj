# =============================================================================
# 03_collect_semantic_scholar.R
# Coleta via Semantic Scholar Academic Graph API (S2AG)
# Endpoint: https://api.semanticscholar.org/graph/v1/paper/search
# Dependência: 00_setup.R executado previamente
# Saída: data/raw/corpus_{A,B,C,D}/semantic_scholar_*.rds
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando coleta Semantic Scholar", "03_collect_semantic_scholar")

library(httr2)
library(jsonlite)
library(dplyr)
library(progress)

# Operador null-coalesce — definido antes de qualquer função que o utilize.
`%||%` <- function(a, b) {
  if (is.null(a)) return(b)
  if (length(a) == 0) return(b)
  if (is.atomic(a) && all(is.na(a))) return(b)
  a
}

QUERIES <- readRDS(here::here("data", "processed", "queries.rds"))

SS_KEY    <- Sys.getenv("SEMANTIC_SCHOLAR_API_KEY")
SS_BASE   <- "https://api.semanticscholar.org/graph/v1/paper/search"
SS_FIELDS <- paste(
  "paperId,externalIds,title,year,citationCount,authors",
  "venue,publicationVenue,openAccessPdf,fieldsOfStudy",
  "s2FieldsOfStudy,publicationTypes,journal",
  sep = ","
)

# -----------------------------------------------------------------------------
# Função de coleta com retry e paginação
# -----------------------------------------------------------------------------

fetch_ss_page <- function(query, offset = 0, limit = 100, api_key = NULL) {
  req <- request(SS_BASE) %>%
    req_url_query(
      query  = query,
      offset = offset,
      limit  = limit,
      fields = SS_FIELDS
    ) %>%
    req_retry(max_tries = 5, backoff = function(i) 15 * i) %>%
    req_throttle(rate = 1 / 3) %>%   # 1 request a cada 3s, mais polite quando sem chave
    req_user_agent("enaju-gcpj-research/1.0 (https://github.com/cairesmachado-svg/enaju-gcpj)")

  if (!is.null(api_key) && length(api_key) > 0 && nzchar(api_key)) {
    req <- req %>% req_headers("x-api-key" = api_key)
  }

  resp <- tryCatch(
    req_perform(req),
    error = function(e) {
      cat("[ERRO] SS request falhou:", conditionMessage(e), "\n")
      NULL
    }
  )
  if (is.null(resp)) return(NULL)

  parsed <- tryCatch(resp_body_json(resp), error = function(e) NULL)
  return(parsed)
}

collect_ss_corpus <- function(corpus_id, query_terms,
                               max_results = 3000, limit_per_page = 100) {

  cat("\n--- Coletando Corpus", corpus_id, "via Semantic Scholar ---\n")

  out_dir <- here::here("data", "raw", paste0("corpus_", corpus_id))
  out_rds <- file.path(out_dir, paste0("ss_raw_", corpus_id, ".rds"))

  if (file.exists(out_rds)) {
    cat("[CACHE] SS Corpus", corpus_id, "já coletado.\n")
    return(readRDS(out_rds))
  }

  # Quebrar termos OR compostos em chamadas separadas e combinar
  terms <- strsplit(query_terms, "\\|")[[1]]
  all_papers <- list()

  for (term in terms[1:min(3, length(terms))]) {
    term <- trimws(term)
    cat("  Buscando:", term, "\n")

    first <- fetch_ss_page(term, offset = 0, limit = limit_per_page, api_key = SS_KEY)
    if (is.null(first)) next

    total <- min(first$total %||% 0, max_results)
    papers <- first$data

    if (total > limit_per_page) {
      n_pages <- ceiling(min(total, 1000) / limit_per_page)
      for (pg in 2:min(n_pages, 10)) {
        Sys.sleep(1.2)
        resp_pg <- fetch_ss_page(
          term,
          offset   = (pg - 1) * limit_per_page,
          limit    = limit_per_page,
          api_key  = SS_KEY
        )
        if (!is.null(resp_pg$data)) papers <- c(papers, resp_pg$data)
      }
    }
    all_papers <- c(all_papers, papers)
  }

  if (length(all_papers) == 0) {
    cat("[AVISO] Nenhum resultado SS para corpus", corpus_id, "\n")
    cat("        Verifique SEMANTIC_SCHOLAR_API_KEY — sem chave o endpoint",
        "frequentemente retorna HTTP 429.\n")

    # Salvar stub vazio para que pipelines a jusante continuem.
    empty_df <- tibble::tibble(
      ss_id = character(), doi = character(), title = character(),
      year = integer(), citation_count = integer(),
      venue = character(), journal = character(), first_author = character(),
      fields_of_study = character(),
      source_db = character(), corpus_id = character(), query_date = as.Date(integer())
    )
    saveRDS(empty_df, out_rds)
    readr::write_csv(empty_df, file.path(out_dir, paste0("ss_raw_", corpus_id, ".csv")))
    return(empty_df)
  }

  # Converter para data frame
  df <- tryCatch({
    purrr::map_dfr(all_papers, function(p) {
      tibble::tibble(
        ss_id          = p$paperId %||% NA_character_,
        doi            = p$externalIds$DOI %||% NA_character_,
        title          = p$title %||% NA_character_,
        year           = p$year %||% NA_integer_,
        citation_count = p$citationCount %||% NA_integer_,
        venue          = p$venue %||% NA_character_,
        journal        = p$journal$name %||% NA_character_,
        first_author   = if (length(p$authors) > 0) p$authors[[1]]$name else NA_character_,
        fields_of_study = paste(
          purrr::map_chr(p$s2FieldsOfStudy %||% list(), ~.x$category %||% ""),
          collapse = "; "
        )
      )
    })
  }, error = function(e) {
    cat("[AVISO] Erro ao converter SS corpus", corpus_id, ":", conditionMessage(e), "\n")
    NULL
  })

  if (is.null(df)) return(NULL)

  df <- df %>%
    dplyr::distinct(doi, title, .keep_all = TRUE) %>%
    dplyr::mutate(
      source_db  = "SemanticScholar",
      corpus_id  = corpus_id,
      query_date = Sys.Date()
    )

  saveRDS(df, out_rds)
  readr::write_csv(df, file.path(out_dir, paste0("ss_raw_", corpus_id, ".csv")))

  cat("[OK] SS Corpus", corpus_id, ":", nrow(df), "registros salvos\n")
  log_step(paste("SemanticScholar Corpus", corpus_id, ":", nrow(df), "registros"), "03_collect_ss")
  return(df)
}

# Executar
results_ss <- list()
for (corp in c("A", "B", "C", "D")) {
  Sys.sleep(2)
  results_ss[[corp]] <- collect_ss_corpus(corp, QUERIES[[corp]]$ss)
}

cat("\n=== Sumário Semantic Scholar ===\n")
for (corp in c("A", "B", "C", "D")) {
  n <- if (!is.null(results_ss[[corp]])) nrow(results_ss[[corp]]) else 0
  cat(sprintf("  Corpus %s: %d registros\n", corp, n))
}

log_step("Coleta Semantic Scholar concluída", "03_collect_ss")
cat("\nPróximo passo: execute 04_collect_crossref.R\n")
