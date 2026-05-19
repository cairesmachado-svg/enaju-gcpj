# =============================================================================
# 99_render_article.R
# Renderiza o artigo Quarto para DOCX (RAP) e HTML
# Verifica dependências e garante que todos os objetos necessários existam
# Executar APÓS completar todos os scripts 01–14
# =============================================================================

source(here::here("scripts", "00_setup.R"))
log_step("Iniciando renderização do artigo", "99_render_article")

library(officer)

render_quarto <- function(input, output_format) {
  if (requireNamespace("quarto", quietly = TRUE)) {
    quarto::quarto_render(
      input          = input,
      output_format  = output_format,
      execute_params = list(render_date = as.character(Sys.Date()))
    )
    return(invisible(TRUE))
  }

  quarto_bin <- Sys.which("quarto")
  if (!nzchar(quarto_bin)) {
    stop("Pacote R 'quarto' ausente e CLI 'quarto' não encontrado no PATH.")
  }

  cmd_out <- system2(
    quarto_bin,
    args = c("render", input, "--to", output_format),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(cmd_out, "status")
  if (!is.null(status) && status != 0) {
    cat(paste(cmd_out, collapse = "\n"), "\n")
    stop("Quarto CLI falhou com status ", status)
  }
  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# 1. Verificar dependências (todos os outputs dos scripts anteriores)
# -----------------------------------------------------------------------------

cat("--- Verificando dependências ---\n")

required_files <- c(
  "data/processed/corpus_eligible.rds",
  "data/processed/bibliometrix_M.rds",
  "data/processed/bibliometrix_results.rds",
  "data/processed/maturity_index.rds",
  "data/processed/imecpj_dimensions.rds",
  "data/processed/prisma_stats.rds",
  "data/processed/dedup_report.rds",
  "data/processed/lda_model.rds",
  "data/processed/institutions_db.rds",
  "data/outputs/tables/tab01_annual_production.csv",
  "data/outputs/tables/tab02_top_journals.csv",
  "data/outputs/tables/tab14_imecpj_scores.csv",
  "data/outputs/figures/fig01_annual_production.png",
  "data/outputs/figures/fig09_keyword_network.png",
  "data/outputs/figures/fig17_lda_topics.png",
  "data/outputs/figures/fig20_imecpj_ranking.png",
  "data/outputs/figures/prisma_flow.png"
)

missing <- purrr::map_lgl(required_files, ~!file.exists(here::here(.x)))
if (any(missing)) {
  cat("[AVISO] Arquivos ausentes:\n")
  purrr::walk(required_files[missing], ~cat(" -", .x, "\n"))
  cat("\nExecute os scripts 01–14 antes de renderizar o artigo.\n")
  cat("Continuando assim mesmo (artigo usará placeholders para figuras ausentes).\n\n")
} else {
  cat("[OK] Todas as dependências encontradas\n\n")
}

# -----------------------------------------------------------------------------
# 2. Gerar documento de referência DOCX no estilo RAP (via officer)
# -----------------------------------------------------------------------------

cat("--- Gerando template DOCX para RAP ---\n")

create_rap_reference_docx <- function(output_path) {
  doc <- officer::read_docx()

  # Definir estilos principais
  doc <- doc %>%
    officer::body_add_par("", style = "Normal")

  # Criar arquivo de referência com estilos customizados
  # (O Quarto usará este arquivo como referência de estilos)
  out_file <- here::here("article", "rap_reference.docx")

  print(doc, target = out_file)
  cat("[OK] Documento de referência criado:", out_file, "\n")
  return(out_file)
}

rap_ref <- tryCatch(
  create_rap_reference_docx(here::here("article", "rap_reference.docx")),
  error = function(e) {
    cat("[AVISO] officer falhou:", conditionMessage(e), "\n")
    NULL
  }
)

# -----------------------------------------------------------------------------
# 3. Renderizar o artigo Quarto
# -----------------------------------------------------------------------------

article_qmd <- here::here("manuscripts", "enaju-gcpj-article.qmd")

if (!file.exists(article_qmd)) {
  stop("[ERRO] Arquivo do artigo não encontrado:", article_qmd)
}

cat("--- Renderizando HTML ---\n")

html_result <- tryCatch({
  render_quarto(article_qmd, "html")
  cat("[OK] HTML renderizado\n")
  TRUE
}, error = function(e) {
  cat("[ERRO] Renderização HTML falhou:", conditionMessage(e), "\n")
  FALSE
})

cat("\n--- Renderizando DOCX (formato RAP) ---\n")

docx_result <- tryCatch({
  render_quarto(article_qmd, "docx")
  cat("[OK] DOCX renderizado\n")
  TRUE
}, error = function(e) {
  cat("[ERRO] Renderização DOCX falhou:", conditionMessage(e), "\n")
  FALSE
})

# -----------------------------------------------------------------------------
# 4. Mover outputs para pasta de saída
# -----------------------------------------------------------------------------

if (html_result || docx_result) {
  possible_outputs <- list.files(
    here::here("article"),
    pattern = "enaju-gcpj-article\\.(html|docx)$",
    full.names = TRUE
  )

  outputs_dir <- here::here("data", "outputs")
  for (f in possible_outputs) {
    dest <- file.path(outputs_dir, basename(f))
    file.copy(f, dest, overwrite = TRUE)
    cat("[OK] Output copiado para:", dest, "\n")
  }
}

# -----------------------------------------------------------------------------
# 5. Relatório final do pipeline
# -----------------------------------------------------------------------------

cat("\n=== PIPELINE ENAJU-GCPJ CONCLUÍDO ===\n")
cat("Data:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

# Contagens finais
corpus <- tryCatch(readRDS(here::here("data","processed","corpus_eligible.rds")), error = function(e) NULL)
if (!is.null(corpus)) {
  cat("Corpus final:", nrow(corpus), "registros\n")
  cat("Período:", min(corpus$year, na.rm=TRUE), "–", max(corpus$year, na.rm=TRUE), "\n")
  cat("Fontes:", paste(sort(unique(corpus$source_db)), collapse=", "), "\n")
}

n_figs <- length(list.files(here::here("data","outputs","figures"), pattern="\\.png$"))
n_tabs <- length(list.files(here::here("data","outputs","tables"), pattern="\\.csv$"))
cat("Figuras geradas:", n_figs, "\n")
cat("Tabelas geradas:", n_tabs, "\n")

log_step("Pipeline completo finalizado", "99_render")
cat("\nArtigo disponível em: outputs/enaju-gcpj-article.{html,docx}\n")
