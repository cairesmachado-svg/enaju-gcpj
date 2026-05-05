# =============================================================================
# 09_cocitation_analysis.R
# Análise de cocitação: identificação da base intelectual do campo
# Técnica: acoplamento de referências compartilhadas → redes de cocitação
# Dependência: 08_bibliometric_analysis.R executado previamente
# Saída: data/outputs/networks/cocitation_*.rds + figuras de rede
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando análise de cocitação", "09_cocitation_analysis")

library(bibliometrix)
library(igraph)
library(ggraph)
library(tidygraph)
library(dplyr)
library(ggplot2)
library(viridis)
library(ggrepel)

M     <- readRDS(here::here("data", "processed", "bibliometrix_M.rds"))
fig_d <- here::here("data", "outputs", "figures")
net_d <- here::here("data", "outputs", "networks")

# =============================================================================
# PARTE 1: Rede de Cocitação de Referências (Author Co-citation Analysis — ACA)
# =============================================================================

cat("\n--- Análise de Cocitação de Autores (ACA) ---\n")

# Construir matriz de cocitação via bibliometrix
cocite_net <- tryCatch({
  bibliometrix::biblioNetwork(
    M,
    analysis = "co-citation",
    network  = "references",
    sep      = ";"
  )
}, error = function(e) {
  cat("[AVISO] biblioNetwork falhou:", conditionMessage(e), "\n")
  NULL
})

if (!is.null(cocite_net)) {
  # Normalizar e filtrar (manter apenas nós com força > limiar)
  net_mat <- as.matrix(cocite_net)
  net_mat[net_mat < 3] <- 0

  # Converter para igraph
  g_aca <- igraph::graph_from_adjacency_matrix(
    net_mat, mode = "undirected", weighted = TRUE, diag = FALSE
  )

  # Remover nós isolados
  g_aca <- igraph::delete_vertices(g_aca, igraph::degree(g_aca) == 0)

  # Detectar comunidades (Louvain)
  comm <- igraph::cluster_louvain(g_aca)
  V(g_aca)$community   <- comm$membership
  V(g_aca)$degree_norm <- igraph::degree(g_aca)
  V(g_aca)$betweenness <- igraph::betweenness(g_aca, normalized = TRUE)

  saveRDS(g_aca, file.path(net_d, "cocitation_aca_igraph.rds"))
  cat("[OK] Rede ACA:", igraph::vcount(g_aca), "nós,",
      igraph::ecount(g_aca), "arestas\n")

  # --- Visualização ---
  p_aca <- ggraph::ggraph(tidygraph::as_tbl_graph(g_aca), layout = "fr") +
    ggraph::geom_edge_link(aes(width = weight, alpha = weight),
                           color = "grey60", show.legend = FALSE) +
    ggraph::geom_node_point(aes(size = degree_norm, color = factor(community))) +
    ggraph::geom_node_label(
      aes(label = ifelse(degree_norm > quantile(degree_norm, 0.85), name, "")),
      size = 2.5, repel = TRUE, max.overlaps = 20,
      label.padding = unit(0.1, "lines"), label.size = 0.2
    ) +
    scale_size_continuous(range = c(2, 12), name = "Grau") +
    scale_color_viridis_d(name = "Cluster") +
    scale_edge_width_continuous(range = c(0.2, 2)) +
    labs(
      title    = "Rede de Cocitação de Referências",
      subtitle = "Nós: referências citadas conjuntamente | Clusters: Algoritmo Louvain",
      caption  = "Fonte: elaboração própria"
    ) +
    ggraph::theme_graph(base_size = 11) +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40"),
      legend.position = "right"
    )

  ggsave(file.path(fig_d, "fig06_cocitation_network.png"),
         p_aca, width = 14, height = 12, dpi = 300, bg = "white")

  # Exportar métricas dos nós principais
  node_metrics <- tibble::tibble(
    reference    = igraph::V(g_aca)$name,
    degree       = igraph::degree(g_aca),
    betweenness  = igraph::betweenness(g_aca, normalized = TRUE),
    community    = igraph::V(g_aca)$community,
    strength     = igraph::strength(g_aca)
  ) %>%
    dplyr::arrange(dplyr::desc(degree))

  readr::write_csv(node_metrics,
                   here::here("data", "outputs", "tables", "tab04_cocitation_metrics.csv"))
  cat("[OK] Top 10 referências mais cocitadas:\n")
  print(head(node_metrics, 10))
}

# =============================================================================
# PARTE 2: Análise de Coautoria
# =============================================================================

cat("\n--- Rede de Coautoria ---\n")

coauth_net <- tryCatch({
  bibliometrix::biblioNetwork(
    M,
    analysis = "collaboration",
    network  = "authors",
    sep      = ";"
  )
}, error = function(e) NULL)

if (!is.null(coauth_net)) {
  mat_ca <- as.matrix(coauth_net)
  mat_ca[mat_ca < 2] <- 0

  g_ca <- igraph::graph_from_adjacency_matrix(
    mat_ca, mode = "undirected", weighted = TRUE, diag = FALSE
  )
  g_ca <- igraph::delete_vertices(g_ca, igraph::degree(g_ca) == 0)

  # Componente gigante
  comps <- igraph::components(g_ca)
  giant <- igraph::induced_subgraph(g_ca, which(comps$membership == which.max(comps$csize)))

  comm_ca <- igraph::cluster_louvain(giant)
  V(giant)$community <- comm_ca$membership

  saveRDS(giant, file.path(net_d, "coauthorship_igraph.rds"))

  p_ca <- ggraph::ggraph(tidygraph::as_tbl_graph(giant), layout = "nicely") +
    ggraph::geom_edge_link(aes(alpha = weight), color = "grey70", show.legend = FALSE) +
    ggraph::geom_node_point(aes(size = igraph::degree(giant),
                                color = factor(community))) +
    ggraph::geom_node_label(
      aes(label = ifelse(igraph::degree(giant) > quantile(igraph::degree(giant), 0.90),
                         name, "")),
      size = 2.3, repel = TRUE, max.overlaps = 15
    ) +
    scale_size_continuous(range = c(1.5, 10)) +
    scale_color_viridis_d() +
    labs(
      title    = "Rede de Coautoria (Componente Gigante)",
      subtitle = "Nós: autores | Arestas: colaboração em artigos comuns",
      caption  = "Fonte: elaboração própria"
    ) +
    ggraph::theme_graph() +
    theme(plot.title = element_text(face = "bold", hjust = 0.5))

  ggsave(file.path(fig_d, "fig07_coauthorship_network.png"),
         p_ca, width = 14, height = 12, dpi = 300, bg = "white")

  cat("[OK] Rede de coautoria:", igraph::vcount(giant), "autores,",
      igraph::ecount(giant), "colaborações\n")
}

# =============================================================================
# PARTE 3: Colaboração internacional (país × país)
# =============================================================================

cat("\n--- Rede de Colaboração Internacional ---\n")

country_net <- tryCatch({
  bibliometrix::biblioNetwork(
    M,
    analysis = "collaboration",
    network  = "countries",
    sep      = ";"
  )
}, error = function(e) NULL)

if (!is.null(country_net)) {
  mat_cn <- as.matrix(country_net)

  g_cn <- igraph::graph_from_adjacency_matrix(
    mat_cn, mode = "undirected", weighted = TRUE, diag = FALSE
  )
  g_cn <- igraph::delete_vertices(g_cn, igraph::degree(g_cn) == 0)

  saveRDS(g_cn, file.path(net_d, "country_collab_igraph.rds"))

  p_cn <- ggraph::ggraph(tidygraph::as_tbl_graph(g_cn), layout = "fr") +
    ggraph::geom_edge_link(aes(width = weight, alpha = weight),
                           color = "#2980b9", show.legend = FALSE) +
    ggraph::geom_node_point(aes(size = igraph::strength(g_cn)), color = "#e74c3c") +
    ggraph::geom_node_label(aes(label = name), size = 3, repel = TRUE) +
    scale_size_continuous(range = c(3, 15)) +
    labs(
      title   = "Rede de Colaboração Internacional",
      subtitle = "Arestas: coautorias entre países | Espessura: frequência",
      caption = "Fonte: elaboração própria"
    ) +
    ggraph::theme_graph() +
    theme(plot.title = element_text(face = "bold", hjust = 0.5))

  ggsave(file.path(fig_d, "fig08_country_collaboration.png"),
         p_cn, width = 12, height = 10, dpi = 300, bg = "white")
}

log_step("Análise de cocitação e redes de colaboração concluídas", "09_cocitation")
cat("\n[OK] Script 09 concluído. Próximo passo: 10_keyword_cooccurrence.R\n")
