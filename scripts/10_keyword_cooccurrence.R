# =============================================================================
# 10_keyword_cooccurrence.R
# Análise de coocorrência de palavras-chave: mapeamento temático
# Inclui: redes de coocorrência, mapa temático (quadrantes Callon),
#         evolução temporal de temas, word cloud
# Dependência: 08 e 09 executados previamente
# Saída: figuras de rede temática + tabelas de clusters
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando análise de coocorrência de palavras-chave", "10_keyword_cooccurrence")

library(bibliometrix)
library(igraph)
library(ggraph)
library(tidygraph)
library(tidytext)
library(dplyr)
library(ggplot2)
library(wordcloud2)
library(viridis)
library(scales)

M      <- readRDS(here::here("data", "processed", "bibliometrix_M.rds"))
corpus <- readRDS(here::here("data", "processed", "corpus_eligible.rds"))
fig_d  <- here::here("data", "outputs", "figures")
net_d  <- here::here("data", "outputs", "networks")
tab_d  <- here::here("data", "outputs", "tables")

# =============================================================================
# PARTE 1: Rede de Coocorrência de Palavras-chave (via bibliometrix)
# =============================================================================

cat("\n--- Rede de Coocorrência de Palavras-chave ---\n")

kw_net <- tryCatch({
  bibliometrix::biblioNetwork(
    M,
    analysis = "co-occurrences",
    network  = "keywords",
    sep      = ";"
  )
}, error = function(e) {
  cat("[AVISO] bibliometrix kw network falhou:", conditionMessage(e), "\n")
  NULL
})

build_kw_igraph <- function(mat, min_weight = 3) {
  mat[mat < min_weight] <- 0
  g <- igraph::graph_from_adjacency_matrix(
    mat, mode = "undirected", weighted = TRUE, diag = FALSE
  )
  g <- igraph::delete_vertices(g, igraph::degree(g) == 0)
  comm <- igraph::cluster_louvain(g)
  V(g)$community  <- comm$membership
  V(g)$degree_val <- igraph::degree(g)
  V(g)$strength_v <- igraph::strength(g)
  g
}

if (!is.null(kw_net)) {
  g_kw <- build_kw_igraph(as.matrix(kw_net))
  saveRDS(g_kw, file.path(net_d, "keyword_cooccurrence_igraph.rds"))

  n_communities <- max(V(g_kw)$community)
  cat("[OK] Rede de KW:", igraph::vcount(g_kw), "nós,",
      igraph::ecount(g_kw), "arestas,", n_communities, "comunidades\n")

  # Visualização principal
  p_kw <- ggraph::ggraph(tidygraph::as_tbl_graph(g_kw), layout = "fr") +
    ggraph::geom_edge_link(aes(width = weight, alpha = weight),
                           color = "grey70", show.legend = FALSE) +
    ggraph::geom_node_point(aes(size = strength_v, color = factor(community))) +
    ggraph::geom_node_label(
      aes(label = ifelse(degree_val > quantile(degree_val, 0.80), name, "")),
      size = 3, repel = TRUE, max.overlaps = 25,
      label.padding = unit(0.12, "lines"), label.size = 0.2
    ) +
    scale_size_continuous(range = c(2, 14), name = "Força") +
    scale_color_viridis_d(name = "Cluster temático") +
    scale_edge_width_continuous(range = c(0.2, 2.5)) +
    labs(
      title    = "Rede de Coocorrência de Palavras-chave",
      subtitle = paste("Clusters detectados pelo algoritmo Louvain (k =", n_communities, ")"),
      caption  = "Fonte: elaboração própria. Nós: palavras-chave; Arestas: coocorrência no mesmo artigo."
    ) +
    ggraph::theme_graph(base_size = 11) +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5, size = 13),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40"),
      legend.position = "right"
    )

  ggsave(file.path(fig_d, "fig09_keyword_network.png"),
         p_kw, width = 16, height = 14, dpi = 300, bg = "white")

  # Tabela dos termos centrais por cluster
  kw_metrics <- tibble::tibble(
    keyword   = igraph::V(g_kw)$name,
    cluster   = igraph::V(g_kw)$community,
    degree    = igraph::degree(g_kw),
    strength  = igraph::strength(g_kw),
    between   = igraph::betweenness(g_kw, normalized = TRUE)
  ) %>%
    dplyr::arrange(cluster, dplyr::desc(degree))

  readr::write_csv(kw_metrics, file.path(tab_d, "tab05_keyword_clusters.csv"))
}

# =============================================================================
# PARTE 2: Mapa Temático (Quadrantes Callon — Densidade × Centralidade)
# =============================================================================

cat("\n--- Mapa Temático (Callon) ---\n")

thematic_map <- tryCatch({
  bibliometrix::thematicMap(
    M,
    field = "DE",
    n     = 250,
    minfreq = 5,
    stemming = FALSE,
    size = 0.5,
    n.labels = 3,
    repel = TRUE
  )
}, error = function(e) {
  cat("[AVISO] thematicMap falhou:", conditionMessage(e), "\n")
  NULL
})

if (!is.null(thematic_map)) {
  p_theme <- thematic_map$map +
    labs(
      title    = "Mapa Temático do Campo",
      subtitle = "Quadrante I: temas motores | II: nichos | III: emergentes | IV: básicos",
      caption  = "Fonte: elaboração própria. Metodologia: Callon et al. (1991)."
    ) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(fig_d, "fig10_thematic_map.png"),
         p_theme, width = 12, height = 10, dpi = 300, bg = "white")

  saveRDS(thematic_map$clusters,
          file.path(net_d, "thematic_clusters.rds"))
  cat("[OK] Mapa temático salvo\n")
}

# =============================================================================
# PARTE 3: Evolução Temporal de Temas (Thematic Evolution)
# =============================================================================

cat("\n--- Evolução Temporal de Temas ---\n")

year_breaks <- list(
  "1995-2004" = c(1995, 2004),
  "2005-2014" = c(2005, 2014),
  "2015-2025" = c(2015, 2025)
)

thematic_evol <- tryCatch({
  bibliometrix::thematicEvolution(
    M,
    field    = "DE",
    years    = c(2004, 2014, 2025),
    n        = 100,
    minfreq  = 3,
    measure  = "inclusion",
    stemming = FALSE
  )
}, error = function(e) NULL)

if (!is.null(thematic_evol)) {
  tryCatch({
    png(file.path(fig_d, "fig11_thematic_evolution.png"),
        width = 14, height = 10, units = "in", res = 300, bg = "white")
    bibliometrix::plotThematicEvolution(thematic_evol$Nodes, thematic_evol$Edges)
    dev.off()
    cat("[OK] Evolução temática salva\n")
  }, error = function(e) cat("[AVISO] Plot thematic evolution:", conditionMessage(e), "\n"))
}

# =============================================================================
# PARTE 4: Word Cloud de Palavras-chave por Corpus
# =============================================================================

cat("\n--- Word Clouds por Corpus ---\n")

for (corp in c("A", "B", "C", "D")) {
  kw_data <- corpus %>%
    dplyr::filter(corpus_id == corp, !is.na(keywords), keywords != "") %>%
    dplyr::pull(keywords) %>%
    paste(collapse = "; ") %>%
    stringr::str_split(";") %>%
    unlist() %>%
    trimws() %>%
    tolower() %>%
    .[nchar(.) > 3] %>%
    table() %>%
    as.data.frame() %>%
    dplyr::rename(word = 1, freq = 2) %>%
    dplyr::arrange(dplyr::desc(freq)) %>%
    head(100)

  if (nrow(kw_data) < 5) next

  wc <- tryCatch(
    wordcloud2::wordcloud2(kw_data, size = 0.6, color = "random-dark"),
    error = function(e) NULL
  )

  if (!is.null(wc)) {
    htmlwidgets::saveWidget(wc, file.path(fig_d, paste0("fig12_wordcloud_corpus_", corp, ".html")))
    cat("[OK] Word cloud Corpus", corp, "salvo\n")
  }
}

# =============================================================================
# PARTE 5: Frequência de palavras-chave por corpus (barras)
# =============================================================================

kw_freq <- corpus %>%
  dplyr::filter(!is.na(keywords), keywords != "") %>%
  tidyr::separate_rows(keywords, sep = ";") %>%
  dplyr::mutate(keyword = tolower(trimws(keywords))) %>%
  dplyr::filter(nchar(keyword) > 3) %>%
  dplyr::count(corpus_id, keyword, sort = TRUE) %>%
  dplyr::group_by(corpus_id) %>%
  dplyr::slice_max(n, n = 15) %>%
  dplyr::ungroup()

corpus_labels <- c(
  "A" = "A: Educação Corporativa",
  "B" = "B: Setor Público",
  "C" = "C: Educação Judiciária",
  "D" = "D: Inovação Educacional"
)

p_kw_freq <- ggplot(kw_freq, aes(x = reorder(keyword, n), y = n, fill = corpus_id)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  facet_wrap(~corpus_id, scales = "free",
             labeller = labeller(corpus_id = corpus_labels)) +
  scale_fill_viridis_d() +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title   = "Top 15 Palavras-chave por Corpus Temático",
    x = NULL, y = "Frequência",
    caption = "Fonte: elaboração própria"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.title   = element_text(face = "bold"),
    strip.text   = element_text(face = "bold", size = 9),
    axis.text.y  = element_text(size = 8)
  )

ggsave(file.path(fig_d, "fig13_keyword_frequency_by_corpus.png"),
       p_kw_freq, width = 14, height = 10, dpi = 300, bg = "white")

log_step("Análise de coocorrência de palavras-chave concluída", "10_keyword_cooccurrence")
cat("\n[OK] Script 10 concluído. Próximo passo: 11_bibliographic_coupling.R\n")
