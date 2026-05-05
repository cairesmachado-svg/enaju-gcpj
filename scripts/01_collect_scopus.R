# =============================================================================
# 01_collect_scopus.R
# Coleta de dados bibliométricos via API Scopus para os quatro corpora (A, B, C, D)
# Dependência: 00_setup.R executado previamente
# Saída: data/raw/corpus_{A,B,C,D}/scopus_*.rds + scopus_*.csv
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando coleta Scopus", "01_collect_scopus")

library(rscopus)
library(httr2)
library(jsonlite)
library(progress)

# Verificar chave Scopus
scopus_key <- Sys.getenv("SCOPUS_API_KEY")
if (nchar(scopus_key) == 0) stop("[ERRO] SCOPUS_API_KEY não configurada. Verifique o .env")
options("elsevier_api_key" = scopus_key)

# Carregar queries
QUERIES <- readRDS(here::here("data", "processed", "queries.rds"))

# -----------------------------------------------------------------------------
# Função central de coleta Scopus com paginação e retry
# -----------------------------------------------------------------------------

collect_scopus_corpus <- function(corpus_id, query_str, max_results = 5000,
                                   count_per_page = 25, delay_sec = 1) {
  cat("\n--- Coletando Corpus", corpus_id, "via Scopus ---\n")
  cat("Query:", substr(query_str, 1, 100), "...\n")

  out_dir  <- here::here("data", "raw", paste0("corpus_", corpus_id))
  out_rds  <- file.path(out_dir, paste0("scopus_raw_", corpus_id, ".rds"))
  out_csv  <- file.path(out_dir, paste0("scopus_raw_", corpus_id, ".csv"))

  # Verificar se já coletado (cache)
  if (file.exists(out_rds)) {
    cat("[CACHE] Corpus", corpus_id, "já coletado. Carregando do cache.\n")
    return(readRDS(out_rds))
  }

  # Primeira chamada para obter total de resultados
  resp_first <- tryCatch({
    rscopus::scopus_search(
      query      = query_str,
      max_count  = count_per_page,
      count      = count_per_page,
      start      = 0,
      api_key    = scopus_key,
      verbose    = FALSE
    )
  }, error = function(e) {
    cat("[ERRO] Falha na primeira chamada Scopus:", conditionMessage(e), "\n")
    return(NULL)
  })

  if (is.null(resp_first)) return(NULL)

  total_available <- as.integer(resp_first$total_results)
  total_to_fetch  <- min(total_available, max_results)
  cat("Total disponível:", total_available, "| Coletando:", total_to_fetch, "\n")

  all_entries <- resp_first$entries

  # Paginação
  n_pages <- ceiling(total_to_fetch / count_per_page)
  if (n_pages > 1) {
    pb <- progress_bar$new(
      format = "  Scopus [:bar] :current/:total páginas | ETA: :eta",
      total = n_pages - 1, clear = FALSE
    )

    for (pg in 2:n_pages) {
      Sys.sleep(delay_sec)
      start_idx <- (pg - 1) * count_per_page

      resp <- tryCatch({
        rscopus::scopus_search(
          query     = query_str,
          max_count = count_per_page,
          count     = count_per_page,
          start     = start_idx,
          api_key   = scopus_key,
          verbose   = FALSE
        )
      }, error = function(e) {
        cat("\n[AVISO] Erro na página", pg, ":", conditionMessage(e), "\n")
        Sys.sleep(5)
        NULL
      })

      if (!is.null(resp) && length(resp$entries) > 0) {
        all_entries <- c(all_entries, resp$entries)
      }
      pb$tick()
    }
  }

  # Converter para data frame
  df <- rscopus::gen_entries_to_df(all_entries)$df

  if (is.null(df) || nrow(df) == 0) {
    cat("[AVISO] Nenhum resultado convertido para corpus", corpus_id, "\n")
    return(NULL)
  }

  # Adicionar metadados de proveniência
  df$source_db  <- "Scopus"
  df$corpus_id  <- corpus_id
  df$query_date <- Sys.Date()

  # Salvar
  saveRDS(df, out_rds)
  readr::write_csv(df, out_csv)

  cat("[OK] Corpus", corpus_id, "Scopus:", nrow(df), "registros salvos\n")
  log_step(paste("Scopus Corpus", corpus_id, ":", nrow(df), "registros"), "01_collect_scopus")

  return(df)
}

# -----------------------------------------------------------------------------
# Executar coleta para cada corpus
# -----------------------------------------------------------------------------

results <- list()

for (corp in c("A", "B", "C", "D")) {
  results[[corp]] <- collect_scopus_corpus(
    corpus_id  = corp,
    query_str  = QUERIES[[corp]]$scopus,
    max_results = 5000
  )
}

# Sumário
cat("\n=== Sumário da Coleta Scopus ===\n")
for (corp in c("A", "B", "C", "D")) {
  n <- if (!is.null(results[[corp]])) nrow(results[[corp]]) else 0
  cat(sprintf("  Corpus %s: %d registros\n", corp, n))
}

log_step("Coleta Scopus concluída", "01_collect_scopus")
cat("\nPróximo passo: execute 02_collect_openalex.R\n")
