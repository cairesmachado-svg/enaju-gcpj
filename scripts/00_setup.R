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
  # Em CI (GitHub Actions) ou execução remota, as variáveis podem vir do
  # ambiente diretamente — não interrompemos por ausência do arquivo.
  cat("[AVISO] Arquivo .env não encontrado em:", env_file, "\n")
  cat("        Lendo credenciais diretamente do ambiente do processo.\n")
  cat("        Para execução local: copie .env.example para .env e preencha.\n")
}

# -----------------------------------------------------------------------------
# 2. Instalar e carregar pacotes
# -----------------------------------------------------------------------------

# Pacotes agrupados por fase do pipeline.
# Apenas o grupo "essential" é obrigatório para o setup; "collection" para coleta;
# "analysis" e "render" são checados/instalados sob demanda nas etapas posteriores.
packages_essential <- c("here", "dotenv", "dplyr", "tibble", "purrr",
                        "stringr", "readr", "jsonlite", "httr2")

packages_collection <- c("rscopus", "openalexR", "rcrossref",
                         "xml2", "rvest", "curl", "progress")

packages_analysis <- c("tidyverse", "stringdist", "lubridate", "writexl", "janitor",
                       "bibliometrix", "igraph", "ggraph", "tidygraph",
                       "tidytext", "topicmodels", "stm", "quanteda",
                       "ggplot2", "ggrepel", "patchwork", "scales", "viridis",
                       "RColorBrewer", "wordcloud2", "treemapify",
                       "knitr", "kableExtra", "gt", "flextable",
                       "officer", "officedown",
                       "glue", "furrr", "fmsb", "maps")

# A fase é controlada pela variável de ambiente ENAJU_PHASE
# (collection|analysis|all). Default = "all" para compatibilidade.
phase <- toupper(Sys.getenv("ENAJU_PHASE", "all"))

target_pkgs <- switch(phase,
  "COLLECTION" = unique(c(packages_essential, packages_collection)),
  "ANALYSIS"   = unique(c(packages_essential, packages_collection, packages_analysis)),
  unique(c(packages_essential, packages_collection, packages_analysis))
)

cat(sprintf("\nFase: %s — verificando %d pacote(s)...\n", phase, length(target_pkgs)))

installed_now <- rownames(installed.packages())
missing_pkgs  <- setdiff(target_pkgs, installed_now)

if (length(missing_pkgs) > 0) {
  cat("Instalando", length(missing_pkgs), "pacote(s):",
      paste(missing_pkgs, collapse = ", "), "\n")
  try(install.packages(missing_pkgs,
                       repos = "https://cloud.r-project.org",
                       dependencies = TRUE), silent = FALSE)
}

# Reportar pacotes que falharam ao instalar (não interromper o setup;
# scripts subsequentes informam o que falta).
installed_now <- rownames(installed.packages())
still_missing <- setdiff(target_pkgs, installed_now)
if (length(still_missing) > 0) {
  cat("[AVISO] Pacotes não instalados (verifique dependências de sistema):",
      paste(still_missing, collapse = ", "), "\n")
} else {
  cat("[OK] Todos os pacotes da fase '", phase, "' presentes\n", sep = "")
}

# Carregar somente o que estiver disponível; scripts de coleta carregam o que precisarem.
core_libs <- c("here", "dotenv", "dplyr", "purrr", "stringr",
               "readr", "tibble", "jsonlite", "httr2")
suppressPackageStartupMessages({
  for (lib in core_libs) {
    if (requireNamespace(lib, quietly = TRUE)) {
      library(lib, character.only = TRUE)
    } else {
      cat("[AVISO] Pacote essencial ausente:", lib, "\n")
    }
  }
})
cat("[OK] Pacotes essenciais carregados\n")

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
