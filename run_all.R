# =============================================================================
# run_all.R — Script mestre de execução do pipeline ENAJU-GCPJ
#
# Uso: Rscript run_all.R                  (executa tudo)
#      Rscript run_all.R --from 06        (retoma a partir do script 06)
#      Rscript run_all.R --only 08,09,10  (executa scripts específicos)
#
# Pré-requisito: .env preenchido com as credenciais de API.
# =============================================================================

cat("╔══════════════════════════════════════════════════════════════════╗\n")
cat("║          ENAJU-GCPJ — Pipeline Bibliométrico Completo            ║\n")
cat("║  Mapeamento Global da Educação Corporativa Pública e Judiciária  ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n")
cat("Início:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# --------------------------------------------------------------------------
# Parse de argumentos de linha de comando
# --------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)

from_step <- 0L
only_steps <- NULL

if (length(args) > 0) {
  if ("--from" %in% args) {
    idx <- which(args == "--from") + 1
    from_step <- as.integer(args[idx])
    cat(sprintf("[CONFIG] Executando a partir do script %02d\n\n", from_step))
  }
  if ("--only" %in% args) {
    idx <- which(args == "--only") + 1
    only_steps <- as.integer(strsplit(args[idx], ",")[[1]])
    cat("[CONFIG] Executando apenas scripts:", paste(sprintf("%02d", only_steps), collapse = ", "), "\n\n")
  }
}

# --------------------------------------------------------------------------
# Definição dos passos do pipeline
# --------------------------------------------------------------------------
pipeline <- list(
  list(id = 0L,  label = "Setup e verificação do ambiente",
       file = "scripts/00_setup.R",         required = TRUE),
  list(id = 1L,  label = "Coleta Scopus (A, B, C, D)",
       file = "scripts/01_collect_scopus.R", required = TRUE),
  list(id = 2L,  label = "Coleta OpenAlex (A, B, C, D)",
       file = "scripts/02_collect_openalex.R", required = TRUE),
  list(id = 3L,  label = "Coleta Semantic Scholar (A, B, C, D)",
       file = "scripts/03_collect_semantic_scholar.R", required = TRUE),
  list(id = 4L,  label = "Coleta Crossref (A, B, C, D)",
       file = "scripts/04_collect_crossref.R", required = TRUE),
  list(id = 5L,  label = "Coleta SciELO (A, B, C, D)",
       file = "scripts/05_collect_scielo.R", required = TRUE),
  list(id = 6L,  label = "Fusão e deduplicação do corpus",
       file = "scripts/06_merge_deduplicate.R", required = TRUE),
  list(id = 7L,  label = "Classificação temática e PRISMA 2020",
       file = "scripts/07_classify_corpora.R", required = TRUE),
  list(id = 8L,  label = "Análise bibliométrica principal",
       file = "scripts/08_bibliometric_analysis.R", required = TRUE),
  list(id = 9L,  label = "Análise de cocitação e redes",
       file = "scripts/09_cocitation_analysis.R", required = TRUE),
  list(id = 10L, label = "Coocorrência de palavras-chave e mapa temático",
       file = "scripts/10_keyword_cooccurrence.R", required = TRUE),
  list(id = 11L, label = "Acoplamento bibliográfico",
       file = "scripts/11_bibliographic_coupling.R", required = TRUE),
  list(id = 12L, label = "Modelagem de tópicos (LDA)",
       file = "scripts/12_topic_modeling.R", required = TRUE),
  list(id = 13L, label = "Mapeamento institucional internacional",
       file = "scripts/13_institutional_mapping.R", required = TRUE),
  list(id = 14L, label = "Índice IMECPJ e ranking de países",
       file = "scripts/14_maturity_index.R", required = TRUE),
  list(id = 99L, label = "Renderização do artigo (HTML + DOCX)",
       file = "scripts/99_render_article.R", required = TRUE)
)

# --------------------------------------------------------------------------
# Filtrar passos conforme argumentos
# --------------------------------------------------------------------------
if (!is.null(only_steps)) {
  pipeline <- pipeline[sapply(pipeline, function(x) x$id %in% only_steps)]
} else if (from_step > 0L) {
  pipeline <- pipeline[sapply(pipeline, function(x) x$id >= from_step)]
}

# --------------------------------------------------------------------------
# Executar pipeline
# --------------------------------------------------------------------------
results <- data.frame(
  step    = integer(0),
  label   = character(0),
  status  = character(0),
  elapsed = numeric(0),
  stringsAsFactors = FALSE
)

total <- length(pipeline)
for (i in seq_along(pipeline)) {
  step <- pipeline[[i]]
  cat(sprintf("\n[%02d/%02d] %s\n", i, total, step$label))
  cat(strrep("─", 60), "\n")

  script_path <- file.path(here::here(), step$file)
  if (!file.exists(script_path)) {
    cat(sprintf("[ERRO] Script não encontrado: %s\n", script_path))
    results <- rbind(results, data.frame(
      step = step$id, label = step$label,
      status = "ERRO: arquivo ausente", elapsed = 0
    ))
    if (step$required) {
      cat("[FATAL] Script obrigatório ausente. Abortando pipeline.\n")
      break
    }
    next
  }

  t0 <- proc.time()["elapsed"]
  tryCatch({
    source(script_path, local = FALSE)
    elapsed <- as.numeric(proc.time()["elapsed"] - t0)
    cat(sprintf("\n[OK] Concluído em %.1f segundos\n", elapsed))
    new_row <- data.frame(
      step = as.integer(step$id),
      label = as.character(step$label),
      status = "OK",
      elapsed = round(elapsed, 1),
      stringsAsFactors = FALSE
    )
    results <- rbind(results, new_row)
  }, error = function(e) {
    elapsed <- as.numeric(proc.time()["elapsed"] - t0)
    msg <- conditionMessage(e)
    cat(sprintf("\n[ERRO] %s\n", msg))
    new_row <- data.frame(
      step = as.integer(step$id),
      label = as.character(step$label),
      status = paste0("ERRO: ", substr(msg, 1, 60)),
      elapsed = round(elapsed, 1),
      stringsAsFactors = FALSE
    )
    results <<- rbind(results, new_row)
    if (step$required) {
      cat("[FATAL] Script obrigatório falhou. Abortando pipeline.\n")
      stop(msg)
    }
  })
}

# --------------------------------------------------------------------------
# Relatório final de execução
# --------------------------------------------------------------------------
cat("\n")
cat("╔══════════════════════════════════════════════════════════════════╗\n")
cat("║                   RELATÓRIO DE EXECUÇÃO                         ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n")

for (k in seq_len(nrow(results))) {
  icon <- if (results$status[k] == "OK") "✓" else "✗"
  cat(sprintf("  %s [%02d] %-50s %s (%.1fs)\n",
              icon,
              results$step[k],
              substr(results$label[k], 1, 50),
              results$status[k],
              results$elapsed[k]))
}

n_ok   <- sum(results$status == "OK")
n_fail <- sum(results$status != "OK")
total_t <- sum(results$elapsed)

cat(sprintf("\nTotal: %d/%d scripts concluídos com sucesso | Tempo total: %.0f min %.0f s\n",
            n_ok, nrow(results), total_t %/% 60, total_t %% 60))

if (n_fail == 0) {
  cat("\nPipeline finalizado com sucesso.\n")
  cat("Artigo disponível em: article/enaju-gcpj-article.{html,docx}\n")
} else {
  cat(sprintf("\n%d script(s) com erro. Verifique as mensagens acima e reexecute com:\n", n_fail))
  failed_ids <- paste(results$step[results$status != "OK"], collapse = ",")
  cat(sprintf("  Rscript run_all.R --only %s\n", failed_ids))
}
