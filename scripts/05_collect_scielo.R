# =============================================================================
# 05_collect_scielo.R
# Coleta via SciELO API e scraping do portal SciELO.org
# Foco: Literatura brasileira e ibero-americana sobre os quatro corpora
# Dependência: 00_setup.R executado previamente
# Saída: data/raw/corpus_{A,B,C,D}/scielo_*.rds
#        data/raw/scielo/scielo_combined.rds
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando coleta SciELO", "05_collect_scielo")

library(httr2)
library(jsonlite)
library(rvest)
library(dplyr)
library(progress)
library(xml2)

# Operador null-coalesce — definido antes das funções que o utilizam.
`%||%` <- function(a, b) {
  if (is.null(a)) return(b)
  if (length(a) == 0) return(b)
  if (is.atomic(a) && all(is.na(a))) return(b)
  a
}

QUERIES <- readRDS(here::here("data", "processed", "queries.rds"))

# SciELO expõe busca via Solr no portal search.scielo.org.
# Há dois endpoints úteis:
#   1) https://search.scielo.org/?q=...&output=site&format=json (interface oficial)
#   2) https://articlemeta.scielo.org/api/v1/article/  (metadados por PID — usado para
#      enriquecer registros após a busca)
SCIELO_SEARCH_API  <- "https://search.scielo.org/"
SCIELO_ARTICLE_API <- "https://articlemeta.scielo.org/api/v1"

# -----------------------------------------------------------------------------
# Função: coleta via SciELO Search API (principal)
# -----------------------------------------------------------------------------

collect_scielo_api <- function(corpus_id, query_terms,
                                max_results = 2000, per_page = 100) {

  cat("\n--- Coletando Corpus", corpus_id, "via SciELO API ---\n")

  out_dir <- here::here("data", "raw", paste0("corpus_", corpus_id))
  out_rds <- file.path(out_dir, paste0("scielo_raw_", corpus_id, ".rds"))

  if (file.exists(out_rds)) {
    cat("[CACHE] SciELO Corpus", corpus_id, "já coletado.\n")
    return(readRDS(out_rds))
  }

  all_results <- list()
  page        <- 1
  collected   <- 0

  repeat {
    if (collected >= max_results) break

    resp <- tryCatch({
      req <- request(SCIELO_SEARCH_API) %>%
        req_url_query(
          q      = query_terms,
          count  = per_page,
          from   = (page - 1) * per_page + 1,
          output = "site",
          format = "json",
          lang   = "pt"
        ) %>%
        req_timeout(45) %>%
        req_retry(max_tries = 3, backoff = ~5) %>%
        req_user_agent("enaju-gcpj-research/1.0")

      req_perform(req)
    }, error = function(e) {
      cat("[ERRO] SciELO API:", conditionMessage(e), "\n")
      NULL
    })

    if (is.null(resp)) break

    body_str <- tryCatch(resp_body_string(resp), error = function(e) "")
    parsed <- tryCatch(
      jsonlite::fromJSON(body_str, simplifyVector = FALSE),
      error = function(e) NULL
    )

    if (is.null(parsed)) {
      cat("[AVISO] SciELO API retornou conteúdo não-JSON; tentando fallback de scraping.\n")
      break
    }

    # Resposta Solr padrão tem 'response$docs'; respostas alternativas usam 'articles'.
    articles <- parsed$response$docs %||% parsed$articles$article %||%
                parsed$articles      %||% list()

    if (length(articles) == 0) break

    # Normalizar campos
    batch <- purrr::map_dfr(articles, function(art) {
      tibble::tibble(
        pid          = art$code %||% art$id %||% NA_character_,
        doi          = art$doi %||% NA_character_,
        title        = art$title %||% art$`ti_pt` %||% art$`ti_en` %||% NA_character_,
        year         = as.integer(art$year %||% art$pubdate %||% NA),
        journal      = art$journal_title %||% art$`ta` %||% NA_character_,
        authors      = paste(
          purrr::map_chr(art$authors %||% list(), ~.x$name %||% .x %||% ""),
          collapse = "; "
        ),
        language     = art$language %||% art$lang %||% NA_character_,
        abstract     = art$abstract %||% art$`ab_pt` %||% NA_character_,
        keywords     = paste(art$keywords %||% character(0), collapse = "; "),
        subject_area = art$subject_areas %||% NA_character_,
        country      = art$collection %||% "br"
      )
    })

    all_results[[page]] <- batch
    collected <- collected + nrow(batch)
    page      <- page + 1

    cat(sprintf("  SciELO Corpus %s: %d coletados\n", corpus_id, collected))

    if (nrow(batch) < per_page) break
    Sys.sleep(1.5)
  }

  if (length(all_results) == 0) {
    cat("[AVISO] Nenhum resultado SciELO para corpus", corpus_id, "\n")
    cat("        O endpoint search.scielo.org pode estar bloqueando o IP.\n")
    cat("        Tentando fallback via scraping...\n")

    scrap <- collect_scielo_scraping(corpus_id, query_terms)
    if (!is.null(scrap) && nrow(scrap) > 0) return(scrap)

    # Último recurso: salvar stub vazio para que scripts a jusante não quebrem.
    cat("[AVISO] Nenhum dado SciELO obtido; gravando stub vazio.\n")
    empty_df <- tibble::tibble(
      pid = character(), doi = character(), title = character(),
      year = integer(), journal = character(), authors = character(),
      language = character(), abstract = character(), keywords = character(),
      subject_area = character(), country = character(),
      source_db = character(), corpus_id = character(), query_date = as.Date(integer())
    )
    saveRDS(empty_df, out_rds)
    readr::write_csv(empty_df, file.path(out_dir, paste0("scielo_raw_", corpus_id, ".csv")))
    return(empty_df)
  }

  df <- dplyr::bind_rows(all_results) %>%
    dplyr::mutate(
      source_db  = "SciELO",
      corpus_id  = corpus_id,
      query_date = Sys.Date()
    ) %>%
    dplyr::distinct(doi, title, .keep_all = TRUE)

  saveRDS(df, out_rds)
  readr::write_csv(df, file.path(out_dir, paste0("scielo_raw_", corpus_id, ".csv")))

  cat("[OK] SciELO API Corpus", corpus_id, ":", nrow(df), "registros\n")
  log_step(paste("SciELO Corpus", corpus_id, ":", nrow(df), "registros"), "05_collect_scielo")
  return(df)
}

# -----------------------------------------------------------------------------
# Função fallback: scraping do portal SciELO.org
# -----------------------------------------------------------------------------

collect_scielo_scraping <- function(corpus_id, query_terms,
                                     max_pages = 20, per_page = 15) {

  cat("  Scraping SciELO.org para corpus", corpus_id, "...\n")

  base_url <- "https://search.scielo.org/"
  all_results <- list()

  for (pg in 1:max_pages) {
    full_url <- sprintf(
      "%s?q=%s&lang=pt&from=%d&count=%d",
      base_url,
      utils::URLencode(query_terms, reserved = TRUE),
      (pg - 1) * per_page + 1,
      per_page
    )

    page_html <- tryCatch({
      rvest::read_html(full_url)
    }, error = function(e) NULL)

    if (is.null(page_html)) break

    # Extrair artigos da página de resultados SciELO
    articles <- page_html %>%
      rvest::html_nodes(".results article") %>%
      purrr::map_dfr(function(node) {
        tibble::tibble(
          title   = node %>% rvest::html_node(".title") %>% rvest::html_text(trim = TRUE) %||% NA_character_,
          authors = node %>% rvest::html_node(".authors") %>% rvest::html_text(trim = TRUE) %||% NA_character_,
          year    = node %>% rvest::html_node(".year") %>% rvest::html_text(trim = TRUE) %>%
            stringr::str_extract("\\d{4}") %>% as.integer(),
          journal = node %>% rvest::html_node(".source") %>% rvest::html_text(trim = TRUE) %||% NA_character_,
          doi     = node %>% rvest::html_node("a[href*='doi']") %>%
            rvest::html_attr("href") %>%
            stringr::str_extract("10\\.\\d{4,}/.+") %||% NA_character_
        )
      })

    if (nrow(articles) == 0) break
    all_results[[pg]] <- articles
    Sys.sleep(2)
  }

  if (length(all_results) == 0) {
    cat("[AVISO] Scraping SciELO falhou para corpus", corpus_id,
        "(provável bloqueio anti-bot 403).\n")
    return(NULL)
  }

  df <- dplyr::bind_rows(all_results) %>%
    dplyr::mutate(
      source_db  = "SciELO_scraping",
      corpus_id  = corpus_id,
      query_date = Sys.Date()
    )

  out_dir <- here::here("data", "raw", paste0("corpus_", corpus_id))
  saveRDS(df, file.path(out_dir, paste0("scielo_raw_", corpus_id, ".rds")))

  cat("[OK] SciELO scraping Corpus", corpus_id, ":", nrow(df), "registros\n")
  return(df)
}

# Executar
results_sc <- list()
for (corp in c("A", "B", "C", "D")) {
  Sys.sleep(2)
  results_sc[[corp]] <- collect_scielo_api(corp, QUERIES[[corp]]$scielo)
}

# Salvar combinado SciELO
combined_scielo <- dplyr::bind_rows(results_sc)
if (nrow(combined_scielo) > 0) {
  saveRDS(combined_scielo, here::here("data", "raw", "scielo", "scielo_all_corpora.rds"))
}

cat("\n=== Sumário SciELO ===\n")
for (corp in c("A", "B", "C", "D")) {
  n <- if (!is.null(results_sc[[corp]])) nrow(results_sc[[corp]]) else 0
  cat(sprintf("  Corpus %s: %d registros\n", corp, n))
}

log_step("Coleta SciELO concluída", "05_collect_scielo")
cat("\nPróximo passo: execute 06_merge_deduplicate.R\n")
