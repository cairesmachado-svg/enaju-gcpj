#!/usr/bin/env Rscript
# aux_country_stats.R
# Extrai estatísticas de país do OpenAlex e atualiza tab03_top_countries.csv
# Processa corpus por corpus para evitar estouro de memória

country_label <- function(cc) {
  labels <- c(
    US = "Estados Unidos", GB = "Reino Unido", AU = "Austrália",
    CA = "Canadá", BR = "Brasil", DE = "Alemanha", NL = "Países Baixos",
    ES = "Espanha", CN = "China", IN = "Índia", ZA = "África do Sul",
    IT = "Itália", FR = "França", TR = "Turquia", ID = "Indonésia",
    MY = "Malásia", NG = "Nigéria", PK = "Paquistão", JP = "Japão",
    KR = "Coreia do Sul", PT = "Portugal", MX = "México", CL = "Chile",
    AR = "Argentina", CO = "Colômbia", PH = "Filipinas", EG = "Egito",
    SA = "Arábia Saudita", IR = "Irã", TW = "Taiwan", SG = "Singapura"
  )
  ifelse(!is.na(labels[cc]), labels[cc], cc)
}

all_countries <- c()

for (corpus_id in c("A", "B", "C", "D")) {
  f <- file.path("data", "raw", paste0("corpus_", corpus_id),
                 paste0("openalex_raw_", corpus_id, ".rds"))
  if (!file.exists(f)) {
    cat("[SKIP] Corpus", corpus_id, "não encontrado\n")
    next
  }
  df <- readRDS(f)
  cat("[OK] Corpus", corpus_id, ":", nrow(df), "registros\n")

  if ("country_first_author" %in% names(df)) {
    countries <- df$country_first_author
    countries <- countries[!is.na(countries) & nchar(trimws(countries)) > 0]
    all_countries <- c(all_countries, countries)
    cat("    Países com dado:", length(countries), "\n")
  } else {
    cat("[AVISO] Coluna country_first_author ausente no corpus", corpus_id, "\n")
  }
  rm(df)
  gc()
}

if (length(all_countries) == 0) {
  cat("[ERRO] Nenhum dado de país encontrado\n")
  quit(status = 1)
}

# Tabular e traduzir
tab <- sort(table(all_countries), decreasing = TRUE)
top20 <- head(tab, 20)
result <- data.frame(
  country_label = country_label(names(top20)),
  n = as.integer(top20),
  stringsAsFactors = FALSE
)

out_path <- file.path("data", "outputs", "tables", "tab03_top_countries.csv")
write.csv(result, out_path, row.names = FALSE)
cat("\n[OK] tab03_top_countries.csv salvo em", out_path, "\n\n")
cat("Top 20 países:\n")
print(result, row.names = FALSE)
