#!/usr/bin/env Rscript
# =============================================================================
# check_environment.R — Diagnóstico pré-execução do pipeline ENAJU-GCPJ
#
# Executar ANTES do run_all.R para garantir que o ambiente está pronto.
# Uso: Rscript check_environment.R
# =============================================================================

cat("╔══════════════════════════════════════════════════════════════════╗\n")
cat("║          ENAJU-GCPJ — Diagnóstico do Ambiente                    ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n\n")

issues <- character(0)

# --------------------------------------------------------------------------
# 1. Versão do R
# --------------------------------------------------------------------------
cat("── R e Quarto ──────────────────────────────────────────────────────\n")
rv <- R.version
r_version_num <- as.numeric(paste0(rv$major, ".", gsub("\\..*", "", rv$minor)))
cat(sprintf("  R versão: %s.%s", rv$major, rv$minor))
if (r_version_num >= 4.2) {
  cat(" [OK]\n")
} else {
  cat(" [AVISO: recomendado >= 4.2]\n")
  issues <- c(issues, "R abaixo de 4.2")
}

# Quarto
quarto_path <- Sys.which("quarto")
if (nchar(quarto_path) > 0) {
  qv <- tryCatch(system("quarto --version", intern = TRUE), error = function(e) "desconhecida")
  cat(sprintf("  Quarto versão: %s [OK]\n", qv))
} else {
  cat("  Quarto: NÃO ENCONTRADO [ERRO]\n")
  issues <- c(issues, "Quarto não instalado (https://quarto.org/docs/get-started/)")
}

# --------------------------------------------------------------------------
# 2. Pacotes R
# --------------------------------------------------------------------------
cat("\n── Pacotes R ───────────────────────────────────────────────────────\n")

pkgs_required <- c(
  "here", "dotenv", "rscopus", "openalexR", "rcrossref",
  "httr2", "jsonlite", "xml2", "rvest", "curl",
  "tidyverse", "stringdist", "lubridate", "writexl", "janitor",
  "bibliometrix", "igraph", "ggraph", "tidygraph",
  "tidytext", "topicmodels", "ldatuning",
  "ggplot2", "ggrepel", "patchwork", "scales", "viridis",
  "RColorBrewer", "wordcloud2", "treemapify",
  "knitr", "kableExtra", "gt", "flextable",
  "officer", "officedown", "quarto",
  "progress", "glue", "purrr", "furrr", "fmsb", "maps"
)

installed_pkgs <- installed.packages()[, "Package"]
missing_pkgs   <- pkgs_required[!pkgs_required %in% installed_pkgs]

if (length(missing_pkgs) == 0) {
  cat(sprintf("  Todos os %d pacotes necessários estão instalados [OK]\n", length(pkgs_required)))
} else {
  cat(sprintf("  %d pacote(s) AUSENTE(S):\n", length(missing_pkgs)))
  for (p in missing_pkgs) cat(sprintf("    - %s\n", p))
  issues <- c(issues, paste("Pacotes ausentes:", paste(missing_pkgs, collapse = ", ")))
  cat("\n  Para instalar, execute no console R:\n")
  cat(sprintf('  install.packages(c(%s))\n',
              paste0('"', missing_pkgs, '"', collapse = ", ")))
}

# --------------------------------------------------------------------------
# 3. Arquivo .env e credenciais
# --------------------------------------------------------------------------
cat("\n── Credenciais (.env) ──────────────────────────────────────────────\n")

env_file <- ".env"
if (!file.exists(env_file)) {
  cat("  .env: NÃO ENCONTRADO [ERRO]\n")
  issues <- c(issues, "Arquivo .env ausente — copie .env.example para .env e preencha")
} else {
  dotenv::load_dot_env(env_file)
  cat("  .env: encontrado [OK]\n")

  creds <- list(
    list(var = "SCOPUS_API_KEY",            required = TRUE,  label = "Scopus API Key"),
    list(var = "SEMANTIC_SCHOLAR_API_KEY",  required = FALSE, label = "Semantic Scholar API Key"),
    list(var = "OPENALEX_EMAIL",            required = TRUE,  label = "OpenAlex e-mail (polite pool)"),
    list(var = "CROSSREF_EMAIL",            required = TRUE,  label = "Crossref e-mail (polite pool)")
  )

  for (cr in creds) {
    val <- Sys.getenv(cr$var)
    ok  <- nchar(val) > 0
    req_label <- if (cr$required) "[obrigatória]" else "[opcional]  "
    status    <- if (ok) "[OK]" else if (cr$required) "[AUSENTE — ERRO]" else "[não configurada]"
    cat(sprintf("  %-40s %s %s\n", cr$label, req_label, status))
    if (!ok && cr$required)
      issues <- c(issues, paste("Credencial obrigatória ausente:", cr$var))
  }
}

# --------------------------------------------------------------------------
# 4. Conectividade com as APIs
# --------------------------------------------------------------------------
cat("\n── Conectividade com as APIs ────────────────────────────────────────\n")

test_url <- function(name, url) {
  ok <- tryCatch({
    con <- url(url, open = "")
    close(con)
    TRUE
  }, error   = function(e) FALSE,
     warning = function(w) FALSE)
  cat(sprintf("  %-35s %s\n", name, if (ok) "[OK]" else "[INACESSÍVEL — verifique firewall/proxy]"))
  if (!ok) issues <<- c(issues, paste("API inacessível:", name, url))
}

test_url("OpenAlex",          "https://api.openalex.org/works?per-page=1")
test_url("Crossref",          "https://api.crossref.org/works?rows=1")
test_url("Semantic Scholar",  "https://api.semanticscholar.org/graph/v1/paper/search?query=test&limit=1&fields=title")
test_url("Scopus (Elsevier)", "https://api.elsevier.com/content/search/scopus?query=test&count=1")
test_url("SciELO Search",     "https://search.scielo.org/api/v1/?q=test&count=1")

# --------------------------------------------------------------------------
# 5. Estrutura de diretórios
# --------------------------------------------------------------------------
cat("\n── Estrutura de diretórios ──────────────────────────────────────────\n")
expected_dirs <- c("data/raw", "data/processed", "data/outputs/figures",
                   "data/outputs/tables", "data/outputs/networks", "logs", "article", "scripts")
for (d in expected_dirs) {
  ok <- dir.exists(d)
  cat(sprintf("  %-35s %s\n", d, if (ok) "[OK]" else "[AUSENTE — será criado pelo 00_setup.R]"))
}

# --------------------------------------------------------------------------
# 6. Sumário
# --------------------------------------------------------------------------
cat("\n╔══════════════════════════════════════════════════════════════════╗\n")
cat("║                       DIAGNÓSTICO FINAL                         ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n")

if (length(issues) == 0) {
  cat("  ✓ Ambiente pronto para execução. Execute:\n")
  cat("    Rscript run_all.R\n\n")
} else {
  cat(sprintf("  ✗ %d problema(s) encontrado(s) — resolva antes de executar:\n\n", length(issues)))
  for (iss in issues) cat(sprintf("    • %s\n", iss))
  cat("\n  Após corrigir, rode novamente:\n    Rscript check_environment.R\n\n")
}
