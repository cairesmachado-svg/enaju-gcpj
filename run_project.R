#!/usr/bin/env Rscript
# =============================================================================
# run_project.R
# Orquestrador robusto do projeto ENAJU-GCPJ
#
# Uso recomendado:
#   Rscript run_project.R --mode all
#
# Modos:
#   all           Executa coleta + processamento + análises + artigo
#   collect       Executa apenas 01–05
#   process       Executa 06–07
#   analysis      Executa 08–14
#   render        Executa apenas 99
#   no-scopus     Executa tudo exceto Scopus
#
# Flags:
#   --force             Reexecuta scripts mesmo se marcador de sucesso existir
#   --resume            Continua do último ponto bem-sucedido
#   --repair-layout     Se scripts estiverem na raiz, copia para scripts/
#   --no-render         Não renderiza artigo ao final
#   --renv              Inicializa/restaura renv quando disponível
#
# Exemplos:
#   Rscript run_project.R --mode no-scopus --resume
#   Rscript run_project.R --mode analysis --force
#   Rscript run_project.R --mode all --repair-layout --renv
# =============================================================================

options(
  warn = 1,
  repos = c(CRAN = "https://cloud.r-project.org"),
  scipen = 999
)

cat("\n=== ENAJU-GCPJ | Execução Orquestrada ===\n")
cat("Início:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# -----------------------------------------------------------------------------
# 1. Utilitários básicos
# -----------------------------------------------------------------------------

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

print_help <- function() {
  cat("
Uso: Rscript run_project.R [--mode <modo>] [flags]

Modos:
  all           Executa coleta + processamento + análises + artigo (padrão)
  collect       Executa apenas 01-05 (coleta de dados)
  process       Executa 06-07 (merge e classificação)
  analysis      Executa 08-14 (análises bibliométricas)
  render        Executa apenas 99 (renderização do artigo)
  no-scopus     Executa tudo exceto Scopus (02-14 + 99)

Flags:
  --help              Exibe esta mensagem e sai
  --force             Reexecuta scripts mesmo se marcador de sucesso existir
  --resume            Continua do último ponto bem-sucedido (pula etapas OK)
  --repair-layout     Se scripts estiverem na raiz, copia para scripts/
  --no-render         Não renderiza artigo ao final
  --renv              Inicializa/restaura renv quando disponível

Exemplos:
  Rscript run_project.R --help
  Rscript run_project.R --mode no-scopus --resume
  Rscript run_project.R --mode analysis --force
  Rscript run_project.R --mode all --repair-layout --renv
")
  quit(status = 0, save = "no")
}

parse_args <- function(args) {
  if ("--help" %in% args || "-h" %in% args) print_help()

  out <- list(
    mode = "all",
    force = FALSE,
    resume = FALSE,
    repair_layout = FALSE,
    no_render = FALSE,
    use_renv = FALSE
  )

  for (i in seq_along(args)) {
    a <- args[[i]]
    if (a == "--force") out$force <- TRUE
    if (a == "--resume") out$resume <- TRUE
    if (a == "--repair-layout") out$repair_layout <- TRUE
    if (a == "--no-render") out$no_render <- TRUE
    if (a == "--renv") out$use_renv <- TRUE

    if (startsWith(a, "--mode=")) {
      out$mode <- sub("^--mode=", "", a)
    }

    if (a == "--mode" && i < length(args)) {
      out$mode <- args[[i + 1]]
    }
  }

  valid_modes <- c("all", "collect", "process", "analysis", "render", "no-scopus")
  if (!out$mode %in% valid_modes) {
    stop("Modo inválido: '", out$mode, "'\nModos válidos: ", paste(valid_modes, collapse = ", "),
         "\nUse --help para mais informações.")
  }

  out
}

msg <- function(..., level = "INFO") {
  cat(sprintf("[%s] %s\n", level, paste0(..., collapse = "")))
}

stopf <- function(...) stop(sprintf(...), call. = FALSE)

ensure_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    msg("Instalando pacote obrigatório: ", pkg)
    install.packages(pkg, dependencies = TRUE)
  }
}

safe_dir_create <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

file_nonempty <- function(path) file.exists(path) && file.info(path)$size > 0

# -----------------------------------------------------------------------------
# 2. Descoberta da raiz do projeto
# -----------------------------------------------------------------------------

find_project_root <- function(start = getwd()) {
  cur <- normalizePath(start, winslash = "/", mustWork = TRUE)

  markers <- c(
    "article/enaju-gcpj-article.qmd",
    "scripts/00_setup.R",
    "00_setup.R",
    ".git"
  )

  repeat {
    found <- any(file.exists(file.path(cur, markers)))
    if (found) return(cur)

    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }

  stopf("Não consegui identificar a raiz do projeto. Execute este script dentro do repositório.")
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
ROOT <- find_project_root()
setwd(ROOT)

msg("Raiz do projeto: ", ROOT)
msg("Modo: ", args$mode)

# -----------------------------------------------------------------------------
# 3. Reparação opcional de layout
# -----------------------------------------------------------------------------

expected_scripts <- c(
  "00_setup.R",
  "01_collect_scopus.R",
  "02_collect_openalex.R",
  "03_collect_semantic_scholar.R",
  "04_collect_crossref.R",
  "05_collect_scielo.R",
  "06_merge_deduplicate.R",
  "07_classify_corpora.R",
  "08_bibliometric_analysis.R",
  "09_cocitation_analysis.R",
  "10_keyword_cooccurrence.R",
  "11_bibliographic_coupling.R",
  "12_topic_modeling.R",
  "13_institutional_mapping.R",
  "14_maturity_index.R",
  "99_render_article.R"
)

if (!dir.exists(file.path(ROOT, "scripts"))) {
  if (args$repair_layout && file.exists(file.path(ROOT, "00_setup.R"))) {
    msg("Criando diretório scripts/ e copiando scripts da raiz.")
    dir.create(file.path(ROOT, "scripts"), recursive = TRUE)
    for (s in expected_scripts) {
      src <- file.path(ROOT, s)
      dst <- file.path(ROOT, "scripts", s)
      if (file.exists(src) && !file.exists(dst)) file.copy(src, dst, overwrite = FALSE)
    }
  } else {
    stopf(
      "Diretório scripts/ não encontrado. O projeto espera scripts/00_setup.R.\n",
      "Use --repair-layout se os scripts estiverem na raiz, ou mova os arquivos .R para scripts/."
    )
  }
}

# -----------------------------------------------------------------------------
# 4. Verificação de arquivos essenciais
# -----------------------------------------------------------------------------

missing_scripts <- expected_scripts[!file.exists(file.path(ROOT, "scripts", expected_scripts))]
if (length(missing_scripts) > 0) {
  stopf("Scripts ausentes em scripts/: %s", paste(missing_scripts, collapse = ", "))
}

if (!file.exists(file.path(ROOT, "article", "enaju-gcpj-article.qmd"))) {
  msg("Arquivo article/enaju-gcpj-article.qmd não encontrado. Renderização poderá falhar.", level = "AVISO")
}

if (!file.exists(file.path(ROOT, ".env"))) {
  stopf(
    "Arquivo .env não encontrado na raiz.\n",
    "Crie .env antes de executar. Não inclua credenciais no código versionado."
  )
}

# -----------------------------------------------------------------------------
# 5. Dependências mínimas do orquestrador
# -----------------------------------------------------------------------------

for (pkg in c("here", "dotenv", "jsonlite")) ensure_pkg(pkg)

if (args$use_renv) {
  ensure_pkg("renv")
  if (!file.exists(file.path(ROOT, "renv.lock"))) {
    msg("Inicializando renv no projeto.")
    renv::init(bare = TRUE)
    renv::snapshot(prompt = FALSE)
  } else {
    msg("Restaurando ambiente renv.")
    renv::restore(prompt = FALSE)
  }
}

# -----------------------------------------------------------------------------
# 6. Estrutura de execução, logs e marcadores
# -----------------------------------------------------------------------------

safe_dir_create(file.path(ROOT, "logs"))
safe_dir_create(file.path(ROOT, "logs", "steps"))
safe_dir_create(file.path(ROOT, "logs", "status"))

run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
master_log <- file.path(ROOT, "logs", paste0("run_", run_id, ".log"))

write_log <- function(text) {
  cat(text, "\n", file = master_log, append = TRUE)
}

status_file <- function(step_name) {
  file.path(ROOT, "logs", "status", paste0(step_name, ".success"))
}

step_log_file <- function(step_name) {
  file.path(ROOT, "logs", "steps", paste0(run_id, "_", step_name, ".log"))
}

steps <- data.frame(
  id = c("00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "13", "14", "99"),
  script = expected_scripts,
  phase = c(
    "setup",
    rep("collect", 5),
    rep("process", 2),
    rep("analysis", 7),
    "render"
  ),
  required_output = c(
    "data/processed/queries.rds",
    "data/raw/corpus_A/scopus_A.rds",
    "data/raw/corpus_A/openalex_A.rds",
    "data/raw/corpus_A/semantic_scholar_A.rds",
    "data/raw/corpus_A/crossref_A.rds",
    "data/raw/corpus_A/scielo_A.rds",
    "data/processed/corpus_full.rds",
    "data/processed/corpus_eligible.rds",
    "data/processed/bibliometrix_M.rds",
    "data/outputs/networks/cocitation_author_network.rds",
    "data/outputs/tables/tab10_keyword_clusters.csv",
    "data/outputs/tables/tab11_coupling_clusters.csv",
    "data/processed/lda_model.rds",
    "data/processed/institutions_db.rds",
    "data/processed/maturity_index.rds",
    "data/outputs/enaju-gcpj-article.html"
  ),
  stringsAsFactors = FALSE
)

select_steps <- function(mode, no_render = FALSE) {
  selected <- switch(
    mode,
    "all" = steps$id,
    "collect" = c("00", "01", "02", "03", "04", "05"),
    "process" = c("00", "06", "07"),
    "analysis" = c("00", "08", "09", "10", "11", "12", "13", "14"),
    "render" = c("00", "99"),
    "no-scopus" = c("00", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "13", "14", "99")
  )

  if (no_render) selected <- setdiff(selected, "99")
  steps[steps$id %in% selected, , drop = FALSE]
}

selected_steps <- select_steps(args$mode, args$no_render)

# -----------------------------------------------------------------------------
# 7. Pré-validação de credenciais por modo
# -----------------------------------------------------------------------------

dotenv::load_dot_env(file.path(ROOT, ".env"))

required_env <- character(0)

if ("01" %in% selected_steps$id) {
  required_env <- c(required_env, "SCOPUS_API_KEY")
}

if (any(c("02", "04") %in% selected_steps$id)) {
  required_env <- c(required_env, "OPENALEX_EMAIL", "CROSSREF_EMAIL")
}

missing_env <- required_env[nchar(Sys.getenv(required_env)) == 0]

if (length(missing_env) > 0) {
  stopf(
    "Variáveis obrigatórias ausentes no .env para este modo: %s\n",
    "Use --mode no-scopus para executar sem Scopus, quando aplicável.",
    paste(missing_env, collapse = ", ")
  )
}

# -----------------------------------------------------------------------------
# 8. Execução isolada dos scripts
# -----------------------------------------------------------------------------

run_step <- function(row) {
  step_name <- paste0(row$id, "_", tools::file_path_sans_ext(basename(row$script)))
  script_path <- file.path(ROOT, "scripts", row$script)
  marker <- status_file(step_name)
  out_expected <- file.path(ROOT, row$required_output %||% "")

  if (!args$force && args$resume && file.exists(marker)) {
    msg("Pulando ", row$script, " — marcador de sucesso encontrado.")
    return(invisible(TRUE))
  }

  if (!args$force && file_nonempty(out_expected) && row$id != "00") {
    msg("Pulando ", row$script, " — output esperado já existe: ", row$required_output)
    cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", file = marker)
    return(invisible(TRUE))
  }

  msg("Executando ", row$script)
  write_log(paste("START", row$script, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

  log_file <- step_log_file(step_name)

  cmd <- file.path(R.home("bin"), "Rscript")
  cmd_args <- c("--vanilla", script_path)

  started <- Sys.time()
  result <- system2(
    command = cmd,
    args = cmd_args,
    stdout = log_file,
    stderr = log_file
  )
  elapsed <- round(difftime(Sys.time(), started, units = "mins"), 2)

  if (!identical(result, 0L)) {
    msg("Falha em ", row$script, ". Veja log: ", log_file, level = "ERRO")
    write_log(paste("FAIL", row$script, "exit=", result, "elapsed_min=", elapsed))
    stopf("Execução interrompida em %s", row$script)
  }

  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", file = marker)
  msg("OK ", row$script, " (", elapsed, " min)")
  write_log(paste("OK", row$script, "elapsed_min=", elapsed))

  invisible(TRUE)
}

# -----------------------------------------------------------------------------
# 9. Execução
# -----------------------------------------------------------------------------

cat("\n--- Plano de execução ---\n")
print(selected_steps[, c("id", "script", "phase")], row.names = FALSE)
cat("\n")

for (i in seq_len(nrow(selected_steps))) {
  run_step(selected_steps[i, ])
}

# -----------------------------------------------------------------------------
# 10. Relatório final
# -----------------------------------------------------------------------------

cat("\n=== Execução concluída ===\n")
cat("Fim:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Log principal:", master_log, "\n")
cat("Logs por etapa:", file.path(ROOT, "logs", "steps"), "\n\n")

# Verificação resumida de artefatos finais
final_checks <- c(
  "data/processed/corpus_full.rds",
  "data/processed/corpus_eligible.rds",
  "data/processed/bibliometrix_M.rds",
  "data/processed/maturity_index.rds",
  "data/processed/institutions_db.rds",
  "data/outputs"
)

cat("--- Artefatos principais ---\n")
for (p in final_checks) {
  exists <- file.exists(file.path(ROOT, p)) || dir.exists(file.path(ROOT, p))
  cat(if (exists) "[OK] " else "[--] ", p, "\n", sep = "")
}

cat("\nPróximo comando útil:\n")
cat("  Rscript run_project.R --mode all --resume\n\n")
