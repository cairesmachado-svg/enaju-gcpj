# =============================================================================
# 00_setup.R
# Configuração do ambiente, instalação de pacotes e verificação de credenciais
# Projeto: ENAJU-GCPJ — Mapeamento Bibliométrico Global
# Executar PRIMEIRO, antes de qualquer outro script
# =============================================================================

cat("=== ENAJU-GCPJ | Setup do Ambiente ===\n")
cat("Iniciado em:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# -----------------------------------------------------------------------------
# 1. Carregar variáveis de ambiente
# -----------------------------------------------------------------------------

# Instalar e carregar 'here' e 'dotenv' ANTES de qualquer uso de here::here()
for (.pkg in c("here", "dotenv")) {
  if (!requireNamespace(.pkg, quietly = TRUE))
    install.packages(.pkg, repos = "https://cloud.r-project.org")
}
library(here)
library(dotenv)

env_file <- file.path(here::here(), ".env")
if (file.exists(env_file)) {
  dotenv::load_dot_env(env_file)
  cat("[OK] .env carregado\n")
} else {
  stop(paste(
    "[ERRO] Arquivo .env não encontrado em:", env_file,
    "\nCopie .env.example para .env e preencha as credenciais."
  ))
}

# -----------------------------------------------------------------------------
# 2. Instalar e carregar pacotes
# -----------------------------------------------------------------------------

packages_cran <- c(
  # Ambiente
  "here", "dotenv",
  # Coleta de dados
  "rscopus", "openalexR", "rcrossref", "httr2", "jsonlite", "xml2",
  "rvest", "curl",
  # Manipulação de dados
  "tidyverse", "dplyr", "stringr", "stringdist", "lubridate",
  "readr", "writexl", "janitor",
  # Bibliometria
  "bibliometrix",
  # Redes
  "igraph", "ggraph", "tidygraph",
  # Text mining e topic modeling
  "tidytext", "topicmodels", "stm", "quanteda",
  # Visualização
  "ggplot2", "ggrepel", "patchwork", "scales", "viridis",
  "RColorBrewer", "wordcloud2", "treemapify",
  # Tabelas
  "knitr", "kableExtra", "gt", "flextable",
  # Documento
  "officer", "officedown",
  # Utilitários
  "progress", "glue", "purrr", "furrr", "parallel", "fmsb", "maps"
)

cat("\nVerificando pacotes...\n")
missing_pkgs <- packages_cran[!packages_cran %in% installed.packages()[, "Package"]]

if (length(missing_pkgs) > 0) {
  cat("Instalando", length(missing_pkgs), "pacote(s):", paste(missing_pkgs, collapse = ", "), "\n")
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org", dependencies = TRUE)
} else {
  cat("[OK] Todos os pacotes CRAN já instalados\n")
}

# Carregar pacotes essenciais
suppressPackageStartupMessages({
  library(here)
  library(dotenv)
  library(tidyverse)
  library(bibliometrix)
  library(rscopus)
  library(openalexR)
  library(rcrossref)
  library(httr2)
  library(jsonlite)
  library(stringdist)
  library(igraph)
})
cat("[OK] Pacotes carregados\n")

# -----------------------------------------------------------------------------
# 3. Verificar credenciais
# -----------------------------------------------------------------------------

cat("\n--- Verificação de Credenciais ---\n")

check_cred <- function(var_name, required = TRUE) {
  val <- Sys.getenv(var_name)
  if (nchar(val) == 0 || val == paste0("your_", tolower(var_name), "_here")) {
    if (required) {
      cat("[AVISO] ", var_name, ": NÃO configurada (obrigatória)\n")
    } else {
      cat("[INFO]  ", var_name, ": não configurada (opcional)\n")
    }
    return(FALSE)
  }
  cat("[OK]    ", var_name, ": configurada\n")
  return(TRUE)
}

creds <- list(
  scopus      = check_cred("SCOPUS_API_KEY", required = TRUE),
  scopus_inst = check_cred("SCOPUS_INST_TOKEN", required = FALSE),
  semscholar  = check_cred("SEMANTIC_SCHOLAR_API_KEY", required = FALSE),
  crossref    = check_cred("CROSSREF_EMAIL", required = TRUE),
  openalex    = check_cred("OPENALEX_EMAIL", required = TRUE),
  scielo      = check_cred("SCIELO_EMAIL", required = FALSE)
)

# Configurar rscopus
if (creds$scopus) {
  options("elsevier_api_key" = Sys.getenv("SCOPUS_API_KEY"))
  if (creds$scopus_inst) {
    options("insttoken" = Sys.getenv("SCOPUS_INST_TOKEN"))
  }
  cat("[OK] rscopus configurado\n")
}

# Configurar openalexR
if (creds$openalex) {
  options(openalexR.mailto = Sys.getenv("OPENALEX_EMAIL"))
  cat("[OK] openalexR polite pool configurado\n")
}

# -----------------------------------------------------------------------------
# 4. Criar estrutura de diretórios (idempotente)
# -----------------------------------------------------------------------------

dirs <- c(
  "data/raw/corpus_A", "data/raw/corpus_B",
  "data/raw/corpus_C", "data/raw/corpus_D",
  "data/raw/semantic_scholar", "data/raw/crossref", "data/raw/scielo",
  "data/processed", "data/outputs/figures",
  "data/outputs/tables", "data/outputs/networks",
  "logs"
)

cat("\n--- Estrutura de Diretórios ---\n")
for (d in dirs) {
  full_path <- here::here(d)
  if (!dir.exists(full_path)) {
    dir.create(full_path, recursive = TRUE)
    cat("[CRIADO]", d, "\n")
  } else {
    cat("[OK]    ", d, "\n")
  }
}

# -----------------------------------------------------------------------------
# 5. Criar arquivo de log do pipeline
# -----------------------------------------------------------------------------

log_file <- here::here("logs", "pipeline_log.md")
if (!file.exists(log_file)) {
  writeLines(c(
    "# ENAJU-GCPJ — Log do Pipeline",
    "",
    paste("Projeto iniciado em:", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    "## Execuções",
    ""
  ), log_file)
  cat("[OK] Arquivo de log criado:", log_file, "\n")
}

# Função auxiliar para log (disponível para scripts subsequentes)
log_step <- function(msg, script = "00_setup") {
  entry <- paste0(
    "- **[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "]** ",
    "[", script, "] ", msg
  )
  cat(entry, "\n")
  write(entry, file = here::here("logs", "pipeline_log.md"), append = TRUE)
}

log_step("Setup concluído com sucesso", "00_setup")

# -----------------------------------------------------------------------------
# 6. Definir strings de busca (usadas por todos os scripts de coleta)
# -----------------------------------------------------------------------------

QUERIES <- list(
  A = list(
    label = "Educação Corporativa e Aprendizagem Organizacional",
    scopus = paste0(
      'TITLE-ABS-KEY("corporate education" OR "corporate university" OR ',
      '"corporate learning" OR "workplace learning" OR ',
      '"organizational learning" OR "human resource development" OR ',
      '"employee training" OR "workforce development" OR ',
      '"learning organization" OR "corporate training") ',
      'AND PUBYEAR > 1994'
    ),
    openalex = paste0(
      '"corporate education" OR "corporate university" OR ',
      '"corporate learning" OR "workplace learning" OR ',
      '"organizational learning" OR "human resource development"'
    ),
    ss = "corporate education|corporate university|corporate learning|workplace learning|human resource development",
    crossref = '"corporate education" "corporate university" "corporate learning"',
    scielo = "educacao+corporativa+OR+universidade+corporativa+OR+aprendizagem+organizacional"
  ),
  B = list(
    label = "Setor Público e Desenvolvimento de Capacidades",
    scopus = paste0(
      'TITLE-ABS-KEY("public sector training" OR "civil service training" OR ',
      '"public administration education" OR "capacity development" OR ',
      '"public service capability" OR "government training" OR ',
      '"public sector learning" OR "state capacity building" OR ',
      '"bureaucratic capacity" OR "public workforce development") ',
      'AND PUBYEAR > 1994'
    ),
    openalex = paste0(
      '"public sector training" OR "civil service training" OR ',
      '"public administration education" OR "capacity development" OR ',
      '"public service capability" OR "government training"'
    ),
    ss = "public sector training|civil service training|capacity development|public administration education",
    crossref = '"civil service training" "public sector training" "capacity development"',
    scielo = "capacitacao+servidores+OR+treinamento+setor+publico+OR+desenvolvimento+capacidades"
  ),
  C = list(
    label = "Educação Judiciária",
    scopus = paste0(
      'TITLE-ABS-KEY("judicial education" OR "judicial training" OR ',
      '"judicial schools" OR "court staff training" OR ',
      '"judicial capacity building" OR "court administration training" OR ',
      '"judge training" OR "magistrate training" OR ',
      '"justice sector training" OR "legal education judiciary") ',
      'AND PUBYEAR > 1994'
    ),
    openalex = paste0(
      '"judicial education" OR "judicial training" OR ',
      '"judicial schools" OR "court staff training" OR ',
      '"judicial capacity building" OR "court administration training"'
    ),
    ss = "judicial education|judicial training|judicial capacity building|court staff training",
    crossref = '"judicial education" "judicial training" "court administration"',
    scielo = "educacao+judicial+OR+formacao+magistrados+OR+escola+judicial"
  ),
  D = list(
    label = "Inovação, Tecnologia e Avaliação Educacional",
    scopus = paste0(
      'TITLE-ABS-KEY("learning analytics" OR "educational technology" OR ',
      '"digital learning" OR "AI in training" OR "training evaluation" OR ',
      '"competency-based learning" OR "e-learning public sector" OR ',
      '"digital transformation training" OR "adaptive learning" OR ',
      '"microlearning" OR "learning management system government") ',
      'AND PUBYEAR > 1999'
    ),
    openalex = paste0(
      '"learning analytics" OR "educational technology" OR ',
      '"digital learning" OR "training evaluation" OR ',
      '"competency-based learning" OR "e-learning public sector"'
    ),
    ss = "learning analytics|educational technology|digital learning|training evaluation|competency-based learning",
    crossref = '"learning analytics" "educational technology" "competency-based learning"',
    scielo = "analytics+aprendizagem+OR+educacao+digital+OR+avaliacao+treinamento"
  )
)

# Salvar queries para uso pelos demais scripts
saveRDS(QUERIES, here::here("data", "processed", "queries.rds"))
cat("\n[OK] Queries de busca definidas e salvas\n")
cat("\nSetup finalizado. Próximo passo: execute 01_collect_scopus.R\n")
