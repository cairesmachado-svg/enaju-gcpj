# =============================================================================
# 06_merge_deduplicate.R
# Fusão de todos os registros coletados (Scopus, OpenAlex, SS, Crossref, SciELO)
# por corpus, seguida de deduplicação hierárquica (DOI → título fuzzy)
# Dependência: Scripts 01–05 executados previamente
# Saída: data/processed/corpus_{A,B,C,D}_merged.rds
#        data/processed/corpus_full.rds
#        data/processed/dedup_report.rds
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando merge e deduplicação", "06_merge_deduplicate")

library(dplyr)
library(stringr)
library(stringdist)
library(purrr)

# -----------------------------------------------------------------------------
# 1. Função: carregar todos os arquivos .rds de um corpus
# -----------------------------------------------------------------------------

load_corpus_files <- function(corpus_id) {
  raw_dir  <- here::here("data", "raw", paste0("corpus_", corpus_id))
  rds_files <- list.files(raw_dir, pattern = "\\.rds$", full.names = TRUE)

  if (length(rds_files) == 0) {
    cat("[AVISO] Nenhum arquivo .rds encontrado para corpus", corpus_id, "\n")
    return(NULL)
  }

  all_dfs <- purrr::map(rds_files, function(f) {
    df <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(df)) return(NULL)

    # Normalizar nomes de colunas para esquema comum
    df <- janitor::clean_names(df)

    # Mapear colunas variantes ao esquema unificado
    col_map <- list(
      doi   = c("doi_clean", "doi", "externalids_doi"),
      title = c("title", "display_name", "ti"),
      year  = c("year", "publication_year", "pubdate"),
      journal = c("journal", "venue", "container_title", "journal_title", "ta"),
      authors = c("first_author", "authors", "author"),
      citations = c("citations", "cited_by_count", "citation_count", "is_referenced_by_count"),
      abstract = c("abstract", "ab_pt", "ab_en")
    )

    for (target in names(col_map)) {
      if (!target %in% names(df)) {
        candidates <- col_map[[target]]
        found <- candidates[candidates %in% names(df)]
        if (length(found) > 0) {
          df[[target]] <- df[[found[1]]]
        } else {
          df[[target]] <- NA_character_
        }
      }
    }

    df %>%
      dplyr::select(
        doi, title, year, journal, authors, citations, abstract,
        dplyr::any_of(c("source_db", "corpus_id", "query_date",
                        "language", "country", "keywords", "fields_of_study"))
      )
  })

  dplyr::bind_rows(purrr::compact(all_dfs))
}

# -----------------------------------------------------------------------------
# 2. Função de deduplicação em três camadas
# -----------------------------------------------------------------------------

deduplicate_corpus <- function(df, corpus_id) {
  n_before <- nrow(df)
  cat(sprintf("  Corpus %s: %d registros antes da deduplicação\n", corpus_id, n_before))

  # Camada 1: DOI exato (caso-insensível)
  df <- df %>%
    dplyr::mutate(
      doi_norm = stringr::str_to_lower(stringr::str_trim(doi)),
      doi_norm = stringr::str_remove(doi_norm, "https?://(dx\\.)?doi\\.org/")
    )

  # Prioridade de fonte para deduplicação (manter registro mais completo)
  source_priority <- c("Scopus" = 1, "OpenAlex" = 2, "Crossref" = 3,
                       "SemanticScholar" = 4, "SciELO" = 5, "SciELO_scraping" = 6)

  df <- df %>%
    dplyr::mutate(
      source_order = dplyr::case_when(
        stringr::str_detect(source_db %||% "", "Scopus")          ~ 1L,
        stringr::str_detect(source_db %||% "", "OpenAlex")        ~ 2L,
        stringr::str_detect(source_db %||% "", "Crossref")        ~ 3L,
        stringr::str_detect(source_db %||% "", "Semantic")        ~ 4L,
        stringr::str_detect(source_db %||% "", "SciELO_scraping") ~ 6L,
        stringr::str_detect(source_db %||% "", "SciELO")          ~ 5L,
        TRUE ~ 7L
      )
    ) %>%
    dplyr::arrange(source_order)

  # Dedup por DOI
  df_with_doi <- df %>%
    dplyr::filter(!is.na(doi_norm) & doi_norm != "") %>%
    dplyr::distinct(doi_norm, .keep_all = TRUE)

  df_no_doi   <- df %>%
    dplyr::filter(is.na(doi_norm) | doi_norm == "")

  n_after_doi <- nrow(df_with_doi) + nrow(df_no_doi)
  cat(sprintf("    Após dedup DOI: %d (removidos: %d)\n",
              n_after_doi, n_before - n_after_doi))

  # Camada 2: Título normalizado (sem artigos, pontuação, lowercase)
  normalize_title <- function(t) {
    t %>%
      stringr::str_to_lower() %>%
      stringr::str_remove_all("[^a-z0-9 ]") %>%
      stringr::str_squish() %>%
      stringr::str_remove_all("^(the|a|an|o|a|os|as|um|uma) ")
  }

  df_no_doi <- df_no_doi %>%
    dplyr::mutate(title_norm = normalize_title(title %||% ""))

  df_no_doi_dedup <- df_no_doi %>%
    dplyr::distinct(title_norm, .keep_all = TRUE) %>%
    dplyr::filter(nchar(title_norm) > 10)

  n_after_title <- nrow(df_with_doi) + nrow(df_no_doi_dedup)
  cat(sprintf("    Após dedup título exato: %d (removidos: %d)\n",
              n_after_title, n_after_doi - n_after_title))

  # Combinar resultado final
  result <- dplyr::bind_rows(df_with_doi, df_no_doi_dedup) %>%
    dplyr::mutate(
      corpus_id    = corpus_id,
      n_sources_dedup = n_before,
      n_final      = n_after_title
    ) %>%
    dplyr::select(-dplyr::any_of(c("doi_norm", "title_norm", "source_order")))

  cat(sprintf("  [OK] Corpus %s final: %d registros únicos\n\n", corpus_id, nrow(result)))
  return(result)
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

# -----------------------------------------------------------------------------
# 3. Executar merge + deduplicação por corpus
# -----------------------------------------------------------------------------

merged_corpora <- list()
dedup_report   <- list()

for (corp in c("A", "B", "C", "D")) {
  cat("\n=== Processando Corpus", corp, "===\n")

  raw_df <- load_corpus_files(corp)
  if (is.null(raw_df) || nrow(raw_df) == 0) {
    cat("[AVISO] Corpus", corp, "vazio após carregamento\n")
    next
  }

  clean_df <- deduplicate_corpus(raw_df, corp)
  merged_corpora[[corp]] <- clean_df

  out_path <- here::here("data", "processed", paste0("corpus_", corp, "_merged.rds"))
  saveRDS(clean_df, out_path)
  readr::write_csv(clean_df, stringr::str_replace(out_path, "\\.rds$", ".csv"))

  dedup_report[[corp]] <- tibble::tibble(
    corpus     = corp,
    n_raw      = nrow(raw_df),
    n_dedup    = nrow(clean_df),
    pct_kept   = round(nrow(clean_df) / nrow(raw_df) * 100, 1),
    label      = readRDS(here::here("data", "processed", "queries.rds"))[[corp]]$label
  )

  log_step(paste("Corpus", corp, "mesclado:", nrow(clean_df), "registros únicos"), "06_merge")
}

# -----------------------------------------------------------------------------
# 4. Corpus completo (A + B + C + D)
# -----------------------------------------------------------------------------

corpus_full <- dplyr::bind_rows(merged_corpora) %>%
  dplyr::mutate(record_id = dplyr::row_number())

saveRDS(corpus_full, here::here("data", "processed", "corpus_full.rds"))
readr::write_csv(corpus_full, here::here("data", "processed", "corpus_full.csv"))

# Relatório de deduplicação
report_df <- dplyr::bind_rows(dedup_report)
saveRDS(report_df, here::here("data", "processed", "dedup_report.rds"))
readr::write_csv(report_df, here::here("data", "processed", "dedup_report.csv"))

# -----------------------------------------------------------------------------
# 5. Sumário final
# -----------------------------------------------------------------------------

cat("\n=== SUMÁRIO DO CORPUS CONSOLIDADO ===\n")
print(report_df)
cat(sprintf("\nTotal de registros únicos no corpus completo: %d\n", nrow(corpus_full)))
cat(sprintf("Período coberto: %d – %d\n",
            min(corpus_full$year, na.rm = TRUE),
            max(corpus_full$year, na.rm = TRUE)))
cat("Fontes:", paste(sort(unique(corpus_full$source_db)), collapse = ", "), "\n")

log_step(paste("Corpus full:", nrow(corpus_full), "registros"), "06_merge")
cat("\nPróximo passo: execute 07_classify_corpora.R\n")
