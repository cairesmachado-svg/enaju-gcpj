# =============================================================================
# 13_institutional_mapping.R
# Mapeamento institucional e benchmark internacional
# Inclui: análise de instituições de ensino e formação judicial no mundo,
#         comparação de modelos, países líderes, redes internacionais
# Dependência: 08–12 executados previamente
# Saída: tabelas de benchmark + figuras geopolíticas
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando mapeamento institucional", "13_institutional_mapping")

library(dplyr)
library(ggplot2)
library(maps)
library(viridis)
library(scales)
library(stringr)
library(tidyr)

corpus <- readRDS(here::here("data", "processed", "corpus_eligible.rds"))
fig_d  <- here::here("data", "outputs", "figures")
tab_d  <- here::here("data", "outputs", "tables")

# =============================================================================
# PARTE 1: Banco de dados institucional (escolas judiciais e redes globais)
# =============================================================================

cat("\n--- Banco de Dados Institucional ---\n")

# Base de instituições relevantes — construída com conhecimento especializado
# Expandida via coleta de relatórios institucionais e sites oficiais
institutions_db <- tibble::tribble(
  ~institution, ~country, ~type, ~corpus, ~year_founded, ~network, ~url,

  # REDES INTERNACIONAIS
  "International Organization for Judicial Training (IOJT)", "International", "rede_judicial", "C", 1999, "IOJT", "https://www.iojt.org",
  "European Judicial Training Network (EJTN)", "Europe", "rede_judicial", "C", 2000, "EJTN", "https://www.ejtn.eu",
  "Ibero-American Judicial Schools Network (RIAEJ)", "Ibero-America", "rede_judicial", "C", 1999, "RIAEJ", NA_character_,
  "OECD — Public Governance Directorate", "International", "org_intl", "B", NA_integer_, "OCDE", "https://www.oecd.org",
  "Commonwealth Association for Public Administration (CAPAM)", "International", "org_intl", "B", 1994, "CAPAM", "https://www.capam.org",
  "UN DESA — Division for Public Institutions", "International", "org_intl", "B", NA_integer_, "ONU", NA_character_,
  "Corporate Executive Board / Gartner L&D", "USA", "corporativo", "A", 1983, "privado", NA_character_,

  # ESCOLAS JUDICIAIS NACIONAIS
  "Federal Judicial Center (FJC)", "USA", "escola_judicial", "C", 1967, NA_character_, "https://www.fjc.gov",
  "National Judicial College (NJC)", "USA", "escola_judicial", "C", 1963, NA_character_, "https://www.judges.org",
  "Judicial College (UK)", "United Kingdom", "escola_judicial", "C", 1979, "EJTN", "https://www.judiciary.gov.uk",
  "École Nationale de la Magistrature (ENM)", "France", "escola_judicial", "C", 1958, "EJTN", "https://www.enm.justice.fr",
  "Deutsche Richterakademie", "Germany", "escola_judicial", "C", 1973, "EJTN", NA_character_,
  "National Judicial Academy (NJA)", "India", "escola_judicial", "C", 1993, NA_character_, "https://www.nja.nic.in",
  "National Judicial Institute (NJI)", "Nigeria", "escola_judicial", "C", 1997, NA_character_, NA_character_,
  "Australian Institute of Judicial Administration (AIJA)", "Australia", "escola_judicial", "C", 1978, NA_character_, "https://www.aija.org.au",
  "Japan Judicial Research and Training Institute", "Japan", "escola_judicial", "C", 1947, NA_character_, NA_character_,
  "Escola Nacional de Formação e Aperfeiçoamento de Magistrados (ENFAM)", "Brazil", "escola_judicial", "C", 2006, "RIAEJ", "https://www.enfam.jus.br",

  # ESCOLAS DE GOVERNO / SERVIÇO PÚBLICO
  "École Nationale d'Administration (ENA/INSP)", "France", "escola_governo", "B", 1945, NA_character_, "https://www.insp.gouv.fr",
  "Harvard Kennedy School of Government", "USA", "escola_governo", "B", 1936, NA_character_, "https://www.hks.harvard.edu",
  "Lee Kuan Yew School of Public Policy", "Singapore", "escola_governo", "B", 2004, NA_character_, "https://lkyspp.nus.edu.sg",
  "Australia and New Zealand School of Government (ANZSOG)", "Australia", "escola_governo", "B", 2002, NA_character_, "https://anzsog.edu.au",
  "ENAP Brasil", "Brazil", "escola_governo", "B", 1986, NA_character_, "https://enap.gov.br",
  "IUPERJ / IESP-UERJ", "Brazil", "escola_governo", "B", 1969, NA_character_, NA_character_,
  "National School of Government (NSG)", "South Africa", "escola_governo", "B", 2004, NA_character_, NA_character_,
  "Civil Service College (CSC)", "Singapore", "escola_governo", "B", 1971, NA_character_, "https://www.csc.gov.sg",

  # CORPORATE UNIVERSITIES (referência para corpus A)
  "Motorola University", "USA", "universidade_corporativa", "A", 1981, NA_character_, NA_character_,
  "Hamburger University (McDonald's)", "USA", "universidade_corporativa", "A", 1961, NA_character_, NA_character_,
  "Disney Institute", "USA", "universidade_corporativa", "A", 1986, NA_character_, "https://disneyinstitute.com",
  "Petrobras University", "Brazil", "universidade_corporativa", "A", 1995, NA_character_, NA_character_,
  "Bradesco University", "Brazil", "universidade_corporativa", "A", 1956, NA_character_, NA_character_
)

saveRDS(institutions_db, here::here("data", "processed", "institutions_db.rds"))
readr::write_csv(institutions_db, file.path(tab_d, "tab11_institutions_benchmark.csv"))
cat("[OK] Banco institucional:", nrow(institutions_db), "instituições mapeadas\n")

# =============================================================================
# PARTE 2: Análise de produção científica × presença institucional
# =============================================================================

cat("\n--- Produção por País: Ciência × Presença Institucional ---\n")

# Produção científica por país (do corpus)
prod_country <- corpus %>%
  dplyr::filter(!is.na(country)) %>%
  dplyr::mutate(
    country_name = countrycode::countrycode(
      country,
      origin = "iso2c", destination = "country.name",
      warn = FALSE
    ) %||% country
  ) %>%
  dplyr::count(country_name, corpus_id, name = "n_articles") %>%
  dplyr::group_by(country_name) %>%
  dplyr::summarise(
    total_articles = sum(n_articles),
    corpus_c       = sum(n_articles[corpus_id == "C"]),
    corpus_b       = sum(n_articles[corpus_id == "B"]),
    .groups = "drop"
  )

# Presença institucional por país
inst_by_country <- institutions_db %>%
  dplyr::filter(type %in% c("escola_judicial", "escola_governo")) %>%
  dplyr::count(country, name = "n_institutions") %>%
  dplyr::rename(country_name = country)

# Combinar
country_profile <- dplyr::left_join(
  prod_country, inst_by_country, by = "country_name"
) %>%
  dplyr::mutate(
    n_institutions = tidyr::replace_na(n_institutions, 0),
    research_inst_ratio = total_articles / (n_institutions + 1)
  ) %>%
  dplyr::arrange(dplyr::desc(total_articles))

readr::write_csv(country_profile, file.path(tab_d, "tab12_country_profile.csv"))

# --- Mapa mundial de produção científica ---
tryCatch({
  world_map <- maps::map_data("world")

  country_profile_map <- country_profile %>%
    dplyr::mutate(
      region = dplyr::case_when(
        country_name == "United States" ~ "USA",
        country_name == "United Kingdom" ~ "UK",
        TRUE ~ country_name
      )
    )

  map_data_full <- dplyr::left_join(world_map, country_profile_map, by = "region")

  p_map <- ggplot(map_data_full, aes(x = long, y = lat, group = group)) +
    geom_polygon(aes(fill = total_articles), color = "white", linewidth = 0.1) +
    scale_fill_viridis_c(
      option = "plasma", name = "Artigos",
      na.value = "grey90",
      trans = "log1p",
      labels = scales::comma
    ) +
    coord_fixed(1.3) +
    labs(
      title    = "Mapa Global da Produção Científica sobre Educação Corporativa Pública e Judiciária",
      subtitle = "Escala logarítmica. Países sem dados em cinza.",
      caption  = "Fonte: elaboração própria com base em Scopus, OpenAlex, Crossref, Semantic Scholar e SciELO"
    ) +
    theme_void(base_size = 11) +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5, size = 12),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40"),
      legend.position = "bottom",
      legend.key.width = unit(2, "cm")
    )

  ggsave(file.path(fig_d, "fig19_world_production_map.png"),
         p_map, width = 16, height = 9, dpi = 300, bg = "white")
  cat("[OK] Mapa mundial salvo\n")
}, error = function(e) {
  cat("[AVISO] Mapa mundial falhou:", conditionMessage(e), "\n")
})

# =============================================================================
# PARTE 3: Análise de gap — corpus C vs. corpus A (baixa integração judiciária)
# =============================================================================

cat("\n--- Análise de Gap: Educação Judiciária no Debate Global ---\n")

# Proporção do corpus C no total
total_n <- nrow(corpus)
corpus_c_n <- corpus %>% dplyr::filter(corpus_id == "C") %>% nrow()
pct_c <- corpus_c_n / total_n * 100

cat(sprintf("Corpus C (Educação Judiciária): %d artigos (%.1f%% do total)\n",
            corpus_c_n, pct_c))

# Periódicos do corpus C que também aparecem em A ou B
journals_c <- corpus %>%
  dplyr::filter(corpus_id == "C", !is.na(journal)) %>%
  dplyr::pull(journal) %>%
  unique()

journals_ab <- corpus %>%
  dplyr::filter(corpus_id %in% c("A","B"), !is.na(journal)) %>%
  dplyr::pull(journal) %>%
  unique()

overlap_journals <- length(intersect(
  tolower(journals_c), tolower(journals_ab)
))

cat(sprintf("Periódicos do corpus C que aparecem em A ou B: %d de %d (%.1f%%)\n",
            overlap_journals, length(journals_c),
            overlap_journals / max(1, length(journals_c)) * 100))

# Salvar relatório de gap
gap_report <- tibble::tibble(
  metric = c(
    "Total de registros no corpus",
    "Registros — Corpus C (Educação Judiciária)",
    "Proporção do corpus C no total (%)",
    "Periódicos únicos — Corpus C",
    "Periódicos Corpus C presentes em A ou B",
    "Taxa de sobreposição de periódicos C↔AB (%)"
  ),
  value = c(
    format(total_n, big.mark = "."),
    format(corpus_c_n, big.mark = "."),
    sprintf("%.1f%%", pct_c),
    length(journals_c),
    overlap_journals,
    sprintf("%.1f%%", overlap_journals / max(1, length(journals_c)) * 100)
  )
)

readr::write_csv(gap_report, file.path(tab_d, "tab13_gap_analysis_corpus_C.csv"))
cat("[OK] Relatório de gap salvo\n")

`%||%` <- function(a, b) if (!is.null(a)) a else b

log_step("Mapeamento institucional concluído", "13_institutional_mapping")
cat("\n[OK] Script 13 concluído. Próximo passo: 14_maturity_index.R\n")
