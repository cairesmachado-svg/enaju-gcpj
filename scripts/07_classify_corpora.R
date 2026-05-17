# =============================================================================
# 07_classify_corpora.R
# Classificação temática dos registros, reclassificação manual assistida,
# e geração do fluxograma PRISMA 2020
# Dependência: 06_merge_deduplicate.R executado previamente
# Saída: data/processed/corpus_classified.rds
#        data/outputs/figures/prisma_flow.png
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando classificação dos corpora", "07_classify_corpora")

library(dplyr)
library(stringr)
library(ggplot2)
library(patchwork)

corpus_full <- readRDS(here::here("data", "processed", "corpus_full.rds"))
cat("Corpus carregado:", nrow(corpus_full), "registros\n")

study_end_year <- 2025L

# -----------------------------------------------------------------------------
# 1. Dicionário de termos por campo temático (para reclassificação)
# -----------------------------------------------------------------------------

# Termos nucleares por corpus
terms_nuclear <- list(
  A = c(
    "corporate universit", "corporate education", "corporate learn",
    "human resource development", "workplace learn", "organizational learn",
    "workforce development", "employee training", "learning organization",
    "corporate training"
  ),
  B = c(
    "civil service train", "public sector train", "public administrat.*educat",
    "capacity development", "public service capabilit", "government train",
    "state capacity", "bureaucratic capacity", "public workforce",
    "servidor.*publico", "capacitacao.*servidor", "treinamento.*setor.*publico"
  ),
  C = c(
    "judicial education", "judicial training", "judicial school",
    "court staff train", "judicial capacity", "court administration.*train",
    "judge train", "magistrate train", "justice.*sector.*train",
    "formacao.*magistrado", "escola.*judicial", "educacao.*judicial"
  ),
  D = c(
    "learning analytics", "educational technolog", "digital learn",
    "ai.*train", "training evaluation", "competency.based learn",
    "e.learning.*public", "digital transformation.*train",
    "adaptive learn", "microlearn", "learning management.*system"
  )
)

# -----------------------------------------------------------------------------
# 2. Função de classificação baseada em texto
# -----------------------------------------------------------------------------

classify_record <- function(title, abstract, keywords) {
  text <- paste(
    tolower(title %||% ""),
    tolower(abstract %||% ""),
    tolower(keywords %||% ""),
    sep = " "
  )

  scores <- purrr::map_int(names(terms_nuclear), function(corp) {
    hits <- sum(purrr::map_lgl(terms_nuclear[[corp]], ~stringr::str_detect(text, .x)))
    hits
  })
  names(scores) <- names(terms_nuclear)

  if (all(scores == 0)) return("uncategorized")
  if (sum(scores > 0) > 1) return("multi_corpus")
  return(names(scores)[which.max(scores)])
}

# Aplicar classificação
cat("Classificando registros...\n")
corpus_full <- corpus_full %>%
  dplyr::mutate(
    classification = purrr::pmap_chr(
      list(title, abstract, keywords),
      ~classify_record(..1, ..2, ..3)
    )
  )

# Tabela de classificação
class_table <- corpus_full %>%
  dplyr::count(corpus_id, classification) %>%
  dplyr::arrange(corpus_id, dplyr::desc(n))

cat("\n--- Distribuição de Classificações ---\n")
print(class_table)

# -----------------------------------------------------------------------------
# 3. Filtros de exclusão (critérios PRISMA)
# -----------------------------------------------------------------------------

# Critérios de exclusão
corpus_full <- corpus_full %>%
  dplyr::mutate(
    # Excluir registros sem título
    exclude_no_title = is.na(title) | nchar(trimws(title %||% "")) < 5,

    # Excluir publicações fora do período declarado no artigo (1995–2025)
    exclude_year = !is.na(year) & (year < 1995 | year > study_end_year),

    # Excluir tipos não-artigo para análise principal (pode relaxar para E2)
    exclude_type = dplyr::case_when(
      stringr::str_detect(tolower(type %||% ""), "retract") ~ TRUE,
      TRUE ~ FALSE
    ),

    # Flag de elegibilidade
    eligible = !exclude_no_title & !exclude_year & !exclude_type
  )

# Registros elegíveis por corpus
eligible_df <- corpus_full %>% dplyr::filter(eligible)

cat(sprintf("\nRegistros elegíveis: %d de %d (%.1f%%)\n",
            nrow(eligible_df), nrow(corpus_full),
            nrow(eligible_df) / nrow(corpus_full) * 100))

# Salvar corpus classificado
saveRDS(corpus_full, here::here("data", "processed", "corpus_classified.rds"))
saveRDS(eligible_df, here::here("data", "processed", "corpus_eligible.rds"))
readr::write_csv(eligible_df, here::here("data", "processed", "corpus_eligible.csv"))

# -----------------------------------------------------------------------------
# 4. Estatísticas PRISMA
# -----------------------------------------------------------------------------

n_identified   <- nrow(corpus_full)
n_duplicates   <- n_identified - nrow(eligible_df)
n_screened     <- nrow(eligible_df)
n_excluded_screen <- eligible_df %>%
  dplyr::filter(classification == "uncategorized") %>% nrow()
n_eligible     <- n_screened - n_excluded_screen
n_included     <- n_eligible

prisma_stats <- list(
  identified      = n_identified,
  duplicates      = n_duplicates,
  screened        = n_screened,
  excluded_screen = n_excluded_screen,
  eligible        = n_eligible,
  included        = n_included
)

saveRDS(prisma_stats, here::here("data", "processed", "prisma_stats.rds"))

# -----------------------------------------------------------------------------
# 5. Diagrama PRISMA 2020 (ggplot2)
# -----------------------------------------------------------------------------

plot_prisma <- function(stats) {
  boxes <- tibble::tibble(
    x     = c(0.5, 0.5, 0.5, 0.5, 0.5),
    y     = c(0.90, 0.72, 0.54, 0.36, 0.18),
    label = c(
      sprintf("Registros identificados\nnos bancos de dados\n(n = %s)",
              format(stats$identified, big.mark = ".")),
      sprintf("Registros após\nremoção de duplicatas\n(n = %s)",
              format(stats$screened, big.mark = ".")),
      sprintf("Registros triados\n(n = %s)",
              format(stats$screened, big.mark = ".")),
      sprintf("Registros elegíveis\n(n = %s)",
              format(stats$eligible, big.mark = ".")),
      sprintf("Estudos incluídos\nna síntese\n(n = %s)",
              format(stats$included, big.mark = "."))
    ),
    fill = c("#1f77b4", "#aec7e8", "#aec7e8", "#2ca02c", "#d62728")
  )

  exclusion <- tibble::tibble(
    x1 = 0.85, x2 = 1.1,
    y1 = c(0.72, 0.54),
    y2 = c(0.72, 0.54),
    label = c(
      sprintf("Duplicatas\nremovidas\n(n = %s)", format(stats$duplicates, big.mark = ".")),
      sprintf("Excluídos por\nnão aderência temática\n(n = %s)", format(stats$excluded_screen, big.mark = "."))
    )
  )

  ggplot() +
    # Caixas principais
    geom_tile(data = boxes, aes(x = x, y = y, fill = fill),
              width = 0.7, height = 0.12, color = "grey30", linewidth = 0.4) +
    scale_fill_identity() +
    geom_text(data = boxes, aes(x = x, y = y, label = label),
              size = 3.5, color = "white", fontface = "bold", lineheight = 1.2) +
    # Setas principais
    annotate("segment", x = 0.5, xend = 0.5, y = 0.84, yend = 0.78,
             arrow = arrow(length = unit(0.2, "cm")), linewidth = 0.7) +
    annotate("segment", x = 0.5, xend = 0.5, y = 0.66, yend = 0.60,
             arrow = arrow(length = unit(0.2, "cm")), linewidth = 0.7) +
    annotate("segment", x = 0.5, xend = 0.5, y = 0.48, yend = 0.42,
             arrow = arrow(length = unit(0.2, "cm")), linewidth = 0.7) +
    annotate("segment", x = 0.5, xend = 0.5, y = 0.30, yend = 0.24,
             arrow = arrow(length = unit(0.2, "cm")), linewidth = 0.7) +
    # Caixas de exclusão (lateral)
    geom_tile(data = exclusion, aes(x = (x1 + x2) / 2 + 0.15, y = y1),
              width = 0.45, height = 0.10, fill = "#ff7f0e", color = "grey30", linewidth = 0.4) +
    geom_text(data = exclusion,
              aes(x = (x1 + x2) / 2 + 0.15, y = y1, label = label),
              size = 2.8, color = "white", fontface = "bold", lineheight = 1.2) +
    annotate("segment",
             x = c(0.85, 0.85), xend = c(0.93, 0.93),
             y = c(0.72, 0.54),   yend = c(0.72, 0.54),
             arrow = arrow(length = unit(0.15, "cm")), linewidth = 0.6) +
    # Título e tema
    labs(
      title    = "Fluxograma PRISMA 2020",
      subtitle = "Processo de identificação, triagem e inclusão de registros",
      caption  = "Fonte: elaboração própria com base em PRISMA 2020 (Page et al., 2021)"
    ) +
    xlim(0, 1.4) + ylim(0.05, 1.05) +
    theme_void(base_size = 11) +
    theme(
      plot.title    = element_text(face = "bold", size = 13, hjust = 0.5),
      plot.subtitle = element_text(size = 10, hjust = 0.5, color = "grey40"),
      plot.caption  = element_text(size = 8, hjust = 0, color = "grey50"),
      plot.margin   = margin(10, 10, 10, 10)
    )
}

p_prisma <- plot_prisma(prisma_stats)
ggsave(
  here::here("data", "outputs", "figures", "prisma_flow.png"),
  p_prisma, width = 8, height = 10, dpi = 300, bg = "white"
)
cat("[OK] Diagrama PRISMA salvo\n")

# -----------------------------------------------------------------------------
# 6. Distribuição por corpus e fonte
# -----------------------------------------------------------------------------

dist_table <- eligible_df %>%
  dplyr::count(corpus_id, source_db) %>%
  tidyr::pivot_wider(names_from = source_db, values_from = n, values_fill = 0) %>%
  dplyr::arrange(corpus_id)

readr::write_csv(dist_table, here::here("data", "outputs", "tables", "corpus_distribution.csv"))

cat("\n--- Distribuição por Corpus e Fonte ---\n")
print(dist_table)

log_step(paste("Classificação concluída:", nrow(eligible_df), "registros elegíveis"), "07_classify")
cat("\nPróximo passo: execute 08_bibliometric_analysis.R\n")
