# =============================================================================
# 11_bibliographic_coupling.R
# Acoplamento bibliográfico: identificação das frentes recentes de pesquisa
# Lógica: dois artigos são "acoplados" quando citam ao menos uma referência comum
# Dependência: 08–10 executados previamente
# Saída: redes de acoplamento + cluster de frentes de pesquisa
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando análise de acoplamento bibliográfico", "11_bibliographic_coupling")

library(bibliometrix)
library(igraph)
library(ggraph)
library(tidygraph)
library(dplyr)
library(ggplot2)
library(viridis)

M      <- readRDS(here::here("data", "processed", "bibliometrix_M.rds"))
corpus <- readRDS(here::here("data", "processed", "corpus_eligible.rds"))
fig_d  <- here::here("data", "outputs", "figures")
net_d  <- here::here("data", "outputs", "networks")
tab_d  <- here::here("data", "outputs", "tables")

# =============================================================================
# PARTE 1: Rede de Acoplamento Bibliográfico (artigos recentes, 2015–2025)
# =============================================================================

cat("\n--- Acoplamento Bibliográfico (frentes recentes 2015–2025) ---\n")

# Filtrar apenas artigos recentes para frentes de pesquisa
M_recent <- M[!is.na(M$PY) & as.integer(M$PY) >= 2015, ]
cat("Artigos recentes (2015+):", nrow(M_recent), "\n")

bib_coup <- tryCatch({
  bibliometrix::biblioNetwork(
    M_recent,
    analysis = "coupling",
    network  = "references",
    sep      = ";"
  )
}, error = function(e) {
  cat("[AVISO] Acoplamento bibliográfico falhou:", conditionMessage(e), "\n")
  NULL
})

if (!is.null(bib_coup)) {
  mat_bc <- as.matrix(bib_coup)
  # Normalizar usando coeficiente de Salton
  norm_bc <- bibliometrix::normalizeSimilarity(mat_bc, type = "association")
  norm_bc[norm_bc < 0.1] <- 0

  g_bc <- igraph::graph_from_adjacency_matrix(
    norm_bc, mode = "undirected", weighted = TRUE, diag = FALSE
  )
  g_bc <- igraph::delete_vertices(g_bc, igraph::degree(g_bc) == 0)

  # Detectar comunidades (frentes de pesquisa)
  comm_bc <- igraph::cluster_louvain(g_bc)
  V(g_bc)$community   <- comm_bc$membership
  V(g_bc)$degree_val  <- igraph::degree(g_bc)
  V(g_bc)$year_pub    <- M_recent$PY[match(V(g_bc)$name, rownames(M_recent))]

  n_clusters <- max(V(g_bc)$community)
  cat("[OK] Rede de acoplamento:", igraph::vcount(g_bc), "artigos,",
      n_clusters, "frentes de pesquisa\n")

  saveRDS(g_bc, file.path(net_d, "bibliographic_coupling_igraph.rds"))

  # --- Visualização por frente de pesquisa ---
  p_bc <- ggraph::ggraph(tidygraph::as_tbl_graph(g_bc), layout = "fr") +
    ggraph::geom_edge_link(aes(alpha = weight), color = "grey70",
                           width = 0.5, show.legend = FALSE) +
    ggraph::geom_node_point(aes(size = degree_val, color = factor(community))) +
    scale_size_continuous(range = c(1.5, 8), name = "Grau") +
    scale_color_viridis_d(name = "Frente de Pesquisa") +
    labs(
      title    = "Acoplamento Bibliográfico — Frentes Recentes de Pesquisa (2015–2025)",
      subtitle = paste("Cada nó é um artigo; cada cluster é uma frente temática emergente (k =", n_clusters, ")"),
      caption  = "Fonte: elaboração própria. Normalização: coeficiente de Salton."
    ) +
    ggraph::theme_graph() +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5, size = 12),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40", size = 10)
    )

  ggsave(file.path(fig_d, "fig14_bibliographic_coupling.png"),
         p_bc, width = 14, height = 12, dpi = 300, bg = "white")

  # Identificar artigos centrais de cada frente
  research_fronts <- tibble::tibble(
    article   = V(g_bc)$name,
    front     = V(g_bc)$community,
    degree    = igraph::degree(g_bc),
    year      = V(g_bc)$year_pub
  ) %>%
    dplyr::arrange(front, dplyr::desc(degree)) %>%
    dplyr::group_by(front) %>%
    dplyr::slice_max(degree, n = 5) %>%
    dplyr::ungroup()

  readr::write_csv(research_fronts, file.path(tab_d, "tab06_research_fronts.csv"))
  cat("[OK] Frentes de pesquisa identificadas e salvas\n")
  print(head(research_fronts, 20))
}

# =============================================================================
# PARTE 2: Acoplamento por Periódico (journal coupling)
# =============================================================================

cat("\n--- Acoplamento de Periódicos ---\n")

journal_coup <- tryCatch({
  bibliometrix::biblioNetwork(
    M,
    analysis = "coupling",
    network  = "sources",
    sep      = ";"
  )
}, error = function(e) NULL)

if (!is.null(journal_coup)) {
  mat_jc <- as.matrix(journal_coup)
  mat_jc[mat_jc < 5] <- 0

  g_jc <- igraph::graph_from_adjacency_matrix(
    mat_jc, mode = "undirected", weighted = TRUE, diag = FALSE
  )
  g_jc <- igraph::delete_vertices(g_jc, igraph::degree(g_jc) == 0)

  if (igraph::vcount(g_jc) > 0) {
    comm_jc <- igraph::cluster_louvain(g_jc)
    V(g_jc)$community <- comm_jc$membership

    p_jc <- ggraph::ggraph(tidygraph::as_tbl_graph(g_jc), layout = "fr") +
      ggraph::geom_edge_link(aes(width = weight, alpha = weight),
                             color = "#3498db", show.legend = FALSE) +
      ggraph::geom_node_label(
        aes(label = name, color = factor(community), size = igraph::degree(g_jc)),
        show.legend = FALSE
      ) +
      scale_size_continuous(range = c(2.5, 5)) +
      scale_color_viridis_d() +
      labs(
        title    = "Acoplamento entre Periódicos",
        subtitle = "Periódicos que compartilham referências citadas em comum",
        caption  = "Fonte: elaboração própria"
      ) +
      ggraph::theme_graph() +
      theme(plot.title = element_text(face = "bold", hjust = 0.5))

    ggsave(file.path(fig_d, "fig15_journal_coupling.png"),
           p_jc, width = 12, height = 10, dpi = 300, bg = "white")

    cat("[OK] Acoplamento de periódicos:", igraph::vcount(g_jc), "periódicos\n")
  }
}

# =============================================================================
# PARTE 3: Análise comparativa entre corpora — índice de sobreposição
# =============================================================================

cat("\n--- Sobreposição entre Corpora ---\n")

# Calcular sobreposição por DOI
doi_by_corpus <- corpus %>%
  dplyr::filter(!is.na(doi)) %>%
  dplyr::select(doi, corpus_id) %>%
  dplyr::distinct()

overlap_matrix <- matrix(0, 4, 4, dimnames = list(c("A","B","C","D"), c("A","B","C","D")))

for (c1 in c("A","B","C","D")) {
  for (c2 in c("A","B","C","D")) {
    doi_c1 <- doi_by_corpus %>% dplyr::filter(corpus_id == c1) %>% dplyr::pull(doi)
    doi_c2 <- doi_by_corpus %>% dplyr::filter(corpus_id == c2) %>% dplyr::pull(doi)
    overlap_matrix[c1, c2] <- length(intersect(doi_c1, doi_c2))
  }
}

cat("Matriz de sobreposição entre corpora (n artigos em comum):\n")
print(overlap_matrix)

overlap_df <- as.data.frame(overlap_matrix)
readr::write_csv(overlap_df, file.path(tab_d, "tab07_corpus_overlap.csv"))

log_step("Acoplamento bibliográfico concluído", "11_bibliographic_coupling")
cat("\n[OK] Script 11 concluído. Próximo passo: 12_topic_modeling.R\n")
