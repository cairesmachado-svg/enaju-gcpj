# =============================================================================
# 08_bibliometric_analysis.R
# Análise bibliométrica principal via pacote bibliometrix
# Inclui: análise descritiva, Lei de Bradford, Lei de Lotka, H-index,
#         produção por país/instituição/periódico, evolução temporal
# Dependência: 07_classify_corpora.R executado previamente
# Saída: data/processed/bibliometrix_M.rds + figuras e tabelas
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando análise bibliométrica principal", "08_bibliometric_analysis")

library(bibliometrix)
library(dplyr)
library(ggplot2)
library(patchwork)
library(scales)
library(viridis)

corpus <- readRDS(here::here("data", "processed", "corpus_eligible.rds"))
cat("Corpus carregado:", nrow(corpus), "registros\n")

# =============================================================================
# PARTE 1: Converter corpus para formato bibliometrix (M)
# =============================================================================

# O bibliometrix trabalha com seu objeto M (bibliometrixDB)
# Tentamos converter a partir do CSV Scopus (formato mais completo para M)
# Fallback: usar convert2df com estrutura manual

scopus_files <- list.files(
  here::here("data", "raw"),
  pattern = "scopus_raw.*\\.csv$",
  full.names = TRUE, recursive = TRUE
)

M_list <- list()

for (f in scopus_files) {
  tryCatch({
    M_tmp <- bibliometrix::convert2df(f, dbsource = "scopus", format = "csv")
    if (!is.null(M_tmp) && nrow(M_tmp) > 0) {
      M_list[[f]] <- M_tmp
      cat("[OK] Convertido:", basename(f), "-", nrow(M_tmp), "registros\n")
    }
  }, error = function(e) {
    cat("[AVISO] Falha ao converter", basename(f), ":", conditionMessage(e), "\n")
  })
}

if (length(M_list) > 0) {
  M <- dplyr::bind_rows(M_list)
  cat("Objeto M criado:", nrow(M), "registros\n")
} else {
  # Fallback: construir M manualmente a partir do corpus_eligible
  cat("[INFO] Construindo objeto bibliometrix a partir do corpus_eligible\n")
  M <- corpus %>%
    dplyr::mutate(
      TI = title,
      AU = authors,
      PY = as.integer(year),
      SO = journal,
      TC = as.integer(citations %||% 0),
      AB = abstract,
      DE = keywords,
      DT = "ARTICLE"
    ) %>%
    as.data.frame()
  class(M) <- c("bibliometrixDB", "data.frame")
}

saveRDS(M, here::here("data", "processed", "bibliometrix_M.rds"))

# =============================================================================
# PARTE 2: Análise descritiva geral
# =============================================================================

cat("\n--- Análise Descritiva ---\n")
results <- tryCatch(
  bibliometrix::biblioAnalysis(M, sep = ";"),
  error = function(e) {
    cat("[AVISO] biblioAnalysis falhou:", conditionMessage(e), "\n")
    NULL
  }
)

if (!is.null(results)) {
  summary_res <- summary(results, k = 20, pause = FALSE)
  saveRDS(results, here::here("data", "processed", "bibliometrix_results.rds"))
  cat("[OK] Análise bibliométrica completa salva\n")
}

# =============================================================================
# PARTE 3: Análise descritiva manual (para gráficos e artigo)
# =============================================================================

fig_dir <- here::here("data", "outputs", "figures")
tab_dir <- here::here("data", "outputs", "tables")

# --- 3.1 Produção científica por ano ---
annual_prod <- corpus %>%
  dplyr::filter(!is.na(year), year >= 1995, year <= as.integer(format(Sys.Date(), "%Y"))) %>%
  dplyr::count(year, corpus_id, name = "n_articles") %>%
  dplyr::arrange(year)

# Calcular média móvel 3 anos
annual_total <- annual_prod %>%
  dplyr::group_by(year) %>%
  dplyr::summarise(total = sum(n_articles), .groups = "drop") %>%
  dplyr::mutate(
    ma3 = zoo::rollmean(total, k = 3, fill = NA, align = "right")
  )

p_annual <- ggplot(annual_total, aes(x = year)) +
  geom_col(aes(y = total), fill = "#1f4e79", alpha = 0.8) +
  geom_line(aes(y = ma3), color = "#e74c3c", linewidth = 1.2, na.rm = TRUE) +
  geom_point(aes(y = ma3), color = "#e74c3c", size = 2, na.rm = TRUE) +
  scale_x_continuous(breaks = seq(1995, 2025, by = 5)) +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title    = "Produção Científica Anual (1995–2025)",
    subtitle = "Linha vermelha: média móvel de 3 anos",
    x = "Ano", y = "Número de publicações",
    caption  = "Fonte: elaboração própria com base em Scopus, OpenAlex, Crossref, Semantic Scholar e SciELO"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title    = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

ggsave(file.path(fig_dir, "fig01_annual_production.png"),
       p_annual, width = 10, height = 6, dpi = 300, bg = "white")

# --- 3.2 Produção por corpus ---
p_corpus <- ggplot(annual_prod, aes(x = year, y = n_articles, fill = corpus_id)) +
  geom_area(alpha = 0.8, position = "stack") +
  scale_fill_viridis_d(
    name = "Corpus",
    labels = c(
      "A" = "A: Educação Corporativa",
      "B" = "B: Setor Público",
      "C" = "C: Educação Judiciária",
      "D" = "D: Inovação Educacional"
    )
  ) +
  scale_x_continuous(breaks = seq(1995, 2025, by = 5)) +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title   = "Produção por Corpus Temático (1995–2025)",
    x = "Ano", y = "Publicações",
    caption = "Fonte: elaboração própria"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", plot.title = element_text(face = "bold"))

ggsave(file.path(fig_dir, "fig02_production_by_corpus.png"),
       p_corpus, width = 10, height = 7, dpi = 300, bg = "white")

# --- 3.3 Top 15 periódicos ---
top_journals <- corpus %>%
  dplyr::filter(!is.na(journal), nchar(trimws(journal)) > 0) %>%
  dplyr::mutate(journal = stringr::str_to_title(stringr::str_trunc(journal, 60))) %>%
  dplyr::count(journal, corpus_id, name = "n") %>%
  dplyr::group_by(journal) %>%
  dplyr::summarise(total = sum(n), corpus_main = corpus_id[which.max(n)], .groups = "drop") %>%
  dplyr::slice_max(total, n = 15) %>%
  dplyr::arrange(total)

p_journals <- ggplot(top_journals, aes(x = reorder(journal, total), y = total, fill = corpus_main)) +
  geom_col() +
  coord_flip() +
  scale_fill_viridis_d(name = "Corpus principal") +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title   = "Top 15 Periódicos por Volume de Publicação",
    x = NULL, y = "Número de artigos",
    caption = "Fonte: elaboração própria"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold"),
    axis.text.y = element_text(size = 9)
  )

ggsave(file.path(fig_dir, "fig03_top_journals.png"),
       p_journals, width = 10, height = 8, dpi = 300, bg = "white")

# --- 3.4 Top 20 países ---
top_countries <- corpus %>%
  dplyr::filter(!is.na(country)) %>%
  dplyr::mutate(
    country_label = dplyr::case_when(
      country == "US" ~ "Estados Unidos",
      country == "GB" ~ "Reino Unido",
      country == "AU" ~ "Austrália",
      country == "CA" ~ "Canadá",
      country == "BR" ~ "Brasil",
      country == "DE" ~ "Alemanha",
      country == "NL" ~ "Países Baixos",
      country == "ES" ~ "Espanha",
      country == "CN" ~ "China",
      country == "IN" ~ "Índia",
      country == "ZA" ~ "África do Sul",
      TRUE ~ country
    )
  ) %>%
  dplyr::count(country_label, name = "n") %>%
  dplyr::slice_max(n, n = 20) %>%
  dplyr::arrange(n)

p_countries <- ggplot(top_countries, aes(x = reorder(country_label, n), y = n)) +
  geom_col(fill = "#2980b9") +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title   = "Top 20 Países por Produção Científica",
    x = NULL, y = "Número de publicações",
    caption = "Fonte: elaboração própria"
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(fig_dir, "fig04_top_countries.png"),
       p_countries, width = 9, height = 8, dpi = 300, bg = "white")

# --- 3.5 Lei de Bradford (por corpus) ---
bradford_analysis <- function(df, corpus_label) {
  journal_prod <- df %>%
    dplyr::count(journal, sort = TRUE) %>%
    dplyr::filter(!is.na(journal), journal != "") %>%
    dplyr::mutate(
      rank       = dplyr::row_number(),
      cumulative = cumsum(n),
      pct_cum    = cumulative / sum(n) * 100,
      zone       = dplyr::case_when(
        pct_cum <= 33.3 ~ "Zona 1 (Núcleo)",
        pct_cum <= 66.6 ~ "Zona 2 (Intermediária)",
        TRUE            ~ "Zona 3 (Periférica)"
      )
    )

  ggplot(journal_prod, aes(x = log(rank), y = n, color = zone)) +
    geom_point(alpha = 0.7, size = 1.5) +
    geom_smooth(method = "loess", se = FALSE, color = "black", linewidth = 0.8) +
    scale_color_manual(
      values = c("Zona 1 (Núcleo)" = "#e74c3c",
                 "Zona 2 (Intermediária)" = "#f39c12",
                 "Zona 3 (Periférica)"   = "#27ae60")
    ) +
    labs(
      title    = paste("Dispersão de Bradford — Corpus", corpus_label),
      subtitle = "Distribuição de artigos por periódico (escala log)",
      x = "log(Rank do periódico)", y = "Número de artigos",
      color = NULL,
      caption = "Fonte: elaboração própria"
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", plot.title = element_text(face = "bold"))
}

for (corp in c("A", "B", "C", "D")) {
  corp_df <- corpus %>% dplyr::filter(corpus_id == corp)
  if (nrow(corp_df) < 50) next
  p_brad <- bradford_analysis(corp_df, corp)
  ggsave(
    file.path(fig_dir, paste0("fig05_bradford_corpus_", corp, ".png")),
    p_brad, width = 9, height = 6, dpi = 300, bg = "white"
  )
}

# --- 3.6 Salvar tabelas ---
readr::write_csv(annual_total, file.path(tab_dir, "tab01_annual_production.csv"))
readr::write_csv(top_journals, file.path(tab_dir, "tab02_top_journals.csv"))
readr::write_csv(top_countries, file.path(tab_dir, "tab03_top_countries.csv"))

cat("\n[OK] Análise bibliométrica principal concluída\n")
cat("Figuras salvas em:", fig_dir, "\n")
log_step("Análise bibliométrica principal concluída", "08_bibliometric_analysis")
cat("\nPróximo passo: execute 09_cocitation_analysis.R\n")
