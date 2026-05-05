# =============================================================================
# 12_topic_modeling.R
# Modelagem de tópicos: LDA (Latent Dirichlet Allocation) e STM (Structural
# Topic Model) aplicados aos títulos + abstracts do corpus completo
# Inclui: seleção de k, visualização de tópicos, correlação temática
# Dependência: 08–11 executados previamente
# Saída: data/processed/topic_model_*.rds + figuras
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando modelagem de tópicos", "12_topic_modeling")

library(tidytext)
library(topicmodels)
# ldatuning may not be available for all R versions - handled gracefully
ldatuning_available <- requireNamespace("ldatuning", quietly = TRUE)
if (ldatuning_available) library(ldatuning)
library(stm)
library(dplyr)
library(ggplot2)
library(scales)
library(stringr)
library(tidyr)
library(viridis)

corpus <- readRDS(here::here("data", "processed", "corpus_eligible.rds"))
fig_d  <- here::here("data", "outputs", "figures")
tab_d  <- here::here("data", "outputs", "tables")

cat("Corpus carregado:", nrow(corpus), "registros\n")

# =============================================================================
# PARTE 1: Pré-processamento textual
# =============================================================================

cat("\n--- Pré-processamento textual ---\n")

# Stop words (inglês + português + espanhol + domínio)
custom_stopwords <- tibble::tibble(word = c(
  # Inglês padrão
  tidytext::stop_words$word,
  # Português
  "que", "de", "para", "com", "uma", "este", "esta", "são",
  "pelo", "pelos", "pela", "pelas", "dos", "das", "nos", "nas",
  # Espanhol
  "que", "del", "los", "las", "una", "por", "para", "con",
  # Termos genéricos do domínio (sem valor discriminatório)
  "study", "paper", "article", "research", "results", "findings",
  "analysis", "based", "using", "approach", "model", "method",
  "data", "evidence", "framework", "review", "literature",
  "estudo", "pesquisa", "artigo", "resultado", "análise",
  "proposta", "abordagem", "modelo", "metodo"
))

# Criar corpus textual (título + abstract)
text_df <- corpus %>%
  dplyr::filter(!is.na(title)) %>%
  dplyr::mutate(
    text = paste(
      title %||% "",
      abstract %||% "",
      keywords %||% "",
      sep = " "
    ),
    doc_id = dplyr::row_number()
  ) %>%
  dplyr::select(doc_id, text, corpus_id, year)

# Tokenizar e remover stop words
tokens <- text_df %>%
  tidytext::unnest_tokens(word, text) %>%
  dplyr::filter(
    !word %in% custom_stopwords$word,
    !stringr::str_detect(word, "^[0-9]+$"),
    nchar(word) > 3
  ) %>%
  dplyr::count(doc_id, word, sort = TRUE)

# Criar Document-Term Matrix
dtm <- tokens %>%
  tidytext::cast_dtm(doc_id, word, n)

# Remover documentos esparsos (menos de 3 termos)
row_sums <- apply(dtm, 1, sum)
dtm_filtered <- dtm[row_sums >= 3, ]

cat("[OK] DTM criada:", nrow(dtm_filtered), "documentos,", ncol(dtm_filtered), "termos\n")

# =============================================================================
# PARTE 2: Seleção do número ideal de tópicos (k)
# =============================================================================

cat("\n--- Seleção do número de tópicos (k) ---\n")

k_range <- 4:14  # Testar de 4 a 14 tópicos

result_metrics <- if (ldatuning_available) {
  tryCatch({
    ldatuning::FindTopicsNumber(
      dtm_filtered,
      topics   = k_range,
      metrics  = c("CaoJuan2009", "Arun2010", "Deveaud2014", "Griffiths2004"),
      method   = "Gibbs",
      control  = list(seed = 42),
      mc.cores = max(1, parallel::detectCores() - 1),
      verbose  = FALSE
    )
  }, error = function(e) {
    cat("[AVISO] ldatuning falhou:", conditionMessage(e), "\n")
    NULL
  })
} else {
  cat("[INFO] ldatuning não disponível - usando k default\n")
  NULL
}

if (!is.null(result_metrics)) {
  p_k <- if (ldatuning_available) ldatuning::FindTopicsNumber_plot(result_metrics) else NULL
    labs(
      title   = "Seleção do Número Ideal de Tópicos (k)",
      caption = "Fonte: elaboração própria. Métricas: Cao & Juan, Arun, Deveaud, Griffiths."
    ) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(fig_d, "fig16_topic_k_selection.png"),
         p_k, width = 10, height = 7, dpi = 300, bg = "white")

  # Escolha automática de k baseada em Deveaud (maximizar) e CaoJuan (minimizar)
  k_optimal <- result_metrics %>%
    dplyr::mutate(score = scale(Deveaud2014) - scale(CaoJuan2009)) %>%
    dplyr::slice_max(score, n = 1) %>%
    dplyr::pull(topics)
  cat("[OK] k ótimo selecionado:", k_optimal, "\n")
} else {
  k_optimal <- 8  # Default razoável para o corpus
  cat("[INFO] Usando k default:", k_optimal, "\n")
}

saveRDS(k_optimal, here::here("data", "processed", "k_optimal.rds"))

# =============================================================================
# PARTE 3: LDA — Modelo principal
# =============================================================================

cat("\n--- Treinando LDA com k =", k_optimal, "---\n")

set.seed(42)
lda_model <- tryCatch({
  topicmodels::LDA(
    dtm_filtered,
    k       = k_optimal,
    method  = "Gibbs",
    control = list(seed = 42, iter = 2000, burnin = 500, thin = 10, best = TRUE)
  )
}, error = function(e) {
  cat("[ERRO] LDA falhou:", conditionMessage(e), "\n")
  NULL
})

if (!is.null(lda_model)) {
  saveRDS(lda_model, here::here("data", "processed", "lda_model.rds"))

  # --- Extrair termos mais prováveis por tópico ---
  top_terms <- tidytext::tidy(lda_model, matrix = "beta") %>%
    dplyr::group_by(topic) %>%
    dplyr::slice_max(beta, n = 12) %>%
    dplyr::ungroup() %>%
    dplyr::arrange(topic, dplyr::desc(beta))

  readr::write_csv(top_terms, file.path(tab_d, "tab08_lda_top_terms.csv"))

  # Visualização: termos por tópico
  p_lda_terms <- top_terms %>%
    dplyr::mutate(
      term     = reorder_within(term, beta, topic),
      topic_f  = paste("Tópico", topic)
    ) %>%
    ggplot(aes(x = term, y = beta, fill = factor(topic))) +
    geom_col(show.legend = FALSE) +
    coord_flip() +
    facet_wrap(~topic_f, scales = "free") +
    scale_x_reordered() +
    scale_fill_viridis_d() +
    scale_y_continuous(labels = scales::scientific) +
    labs(
      title   = paste0("LDA — Top 12 Termos por Tópico (k = ", k_optimal, ")"),
      x = NULL, y = "Probabilidade (β)",
      caption = "Fonte: elaboração própria. Método: Gibbs Sampling, 2000 iterações."
    ) +
    theme_minimal(base_size = 10) +
    theme(
      plot.title  = element_text(face = "bold"),
      strip.text  = element_text(face = "bold"),
      axis.text.y = element_text(size = 8)
    )

  ggsave(file.path(fig_d, "fig17_lda_topics.png"),
         p_lda_terms,
         width  = 4 * ceiling(sqrt(k_optimal)),
         height = 3 * ceiling(sqrt(k_optimal)),
         dpi = 300, bg = "white")

  # --- Distribuição de tópicos por documento (gamma) ---
  doc_topics <- tidytext::tidy(lda_model, matrix = "gamma") %>%
    dplyr::mutate(document = as.integer(document)) %>%
    dplyr::left_join(
      text_df %>% dplyr::select(doc_id, corpus_id, year),
      by = c("document" = "doc_id")
    )

  readr::write_csv(doc_topics, file.path(tab_d, "tab09_lda_document_topics.csv"))

  # Tópico dominante por corpus
  topic_by_corpus <- doc_topics %>%
    dplyr::group_by(document, corpus_id) %>%
    dplyr::slice_max(gamma, n = 1) %>%
    dplyr::ungroup() %>%
    dplyr::count(corpus_id, topic, name = "n_docs") %>%
    dplyr::group_by(corpus_id) %>%
    dplyr::mutate(pct = n_docs / sum(n_docs) * 100) %>%
    dplyr::ungroup()

  p_topic_corpus <- ggplot(topic_by_corpus,
                           aes(x = factor(topic), y = pct, fill = corpus_id)) +
    geom_col(position = "dodge") +
    scale_fill_viridis_d(
      name = "Corpus",
      labels = c("A"="Educação Corp.", "B"="Setor Público",
                 "C"="Educação Jud.", "D"="Inovação")
    ) +
    labs(
      title   = "Distribuição de Tópicos LDA por Corpus Temático",
      x = "Tópico", y = "% de documentos",
      caption = "Fonte: elaboração própria"
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom", plot.title = element_text(face = "bold"))

  ggsave(file.path(fig_d, "fig18_topics_by_corpus.png"),
         p_topic_corpus, width = 12, height = 7, dpi = 300, bg = "white")

  cat("[OK] LDA concluído:", k_optimal, "tópicos identificados\n")
}

# =============================================================================
# PARTE 4: Rótulos interpretativos dos tópicos (sugestão automática)
# =============================================================================

# Gerar sugestões de rótulos com base nos 3 termos mais prováveis
if (exists("top_terms")) {
  topic_labels <- top_terms %>%
    dplyr::group_by(topic) %>%
    dplyr::slice_max(beta, n = 3) %>%
    dplyr::summarise(
      suggested_label = paste(term, collapse = " / "),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      topic_id = paste0("T", topic),
      note = "Rótulo interpretativo deve ser revisado manualmente"
    )

  readr::write_csv(topic_labels, file.path(tab_d, "tab10_topic_labels.csv"))
  cat("\n--- Rótulos sugeridos para os tópicos ---\n")
  print(topic_labels)
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

log_step(paste("Modelagem de tópicos concluída. k =", k_optimal), "12_topic_modeling")
cat("\n[OK] Script 12 concluído. Próximo passo: 13_institutional_mapping.R\n")
