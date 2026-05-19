#!/usr/bin/env Rscript
# aux_country_figure.R — gera fig04_top_countries.png a partir de tab03_top_countries.csv

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(readr)
  library(scales)
})

top <- read_csv("data/outputs/tables/tab03_top_countries.csv", show_col_types = FALSE)

top <- top %>%
  mutate(country_label = case_when(
    country_label == "SE" ~ "Suécia",
    country_label == "FI" ~ "Finlândia",
    country_label == "HK" ~ "Hong Kong",
    TRUE ~ country_label
  )) %>%
  arrange(n)

p <- ggplot(top, aes(x = reorder(country_label, n), y = n)) +
  geom_col(fill = "#2980b9") +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title    = "Top 20 Países por Produção Científica",
    subtitle = "País do primeiro autor | Fonte: OpenAlex",
    x = NULL, y = "Número de publicações",
    caption  = "Elaboração própria com base em OpenAlex (2026)"
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

out <- "data/outputs/figures/fig04_top_countries.png"
ggsave(out, p, width = 9, height = 8, dpi = 300, bg = "white")
cat("[OK] fig04_top_countries.png gerada em", out, "\n")
