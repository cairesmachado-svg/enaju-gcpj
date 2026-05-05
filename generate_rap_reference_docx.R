#!/usr/bin/env Rscript
# =============================================================================
# generate_rap_reference_docx.R
# Gera o documento de referência DOCX com estilos compatíveis com a RAP (FGV)
# Uso: Rscript generate_rap_reference_docx.R
# Saída: article/rap_reference.docx
# =============================================================================

if (!requireNamespace("officer", quietly = TRUE))
  install.packages("officer", repos = "https://cloud.r-project.org")
if (!requireNamespace("here", quietly = TRUE))
  install.packages("here", repos = "https://cloud.r-project.org")

library(officer)
library(here)

cat("Gerando rap_reference.docx...\n")

out_path <- here::here("article", "rap_reference.docx")

doc <- read_docx()

# ── Definir estilos de parágrafo compatíveis com RAP ──────────────────────────

# Fonte padrão: Times New Roman 12 / espaçamento 1,5
doc <- doc |>
  body_add_par("Título do Artigo", style = "heading 1") |>
  body_add_par("Subtítulo", style = "heading 2") |>
  body_add_par("Seção 1", style = "heading 2") |>
  body_add_par(
    paste(
      "Este é o parágrafo padrão do corpo do texto. A Revista de Administração Pública",
      "adota Times New Roman 12, espaçamento 1,5, margens de 2,5 cm, alinhamento",
      "justificado e parágrafo com recuo de 1,25 cm na primeira linha."
    ),
    style = "Normal"
  ) |>
  body_add_par("Seção 2", style = "heading 2") |>
  body_add_par("Corpo do texto.", style = "Normal") |>
  body_add_par("Referências", style = "heading 1") |>
  body_add_par(
    "SOBRENOME, Nome. Título do livro. Cidade: Editora, Ano.",
    style = "Normal"
  )

# ── Aplicar formatação de página (A4, margens ABNT) ───────────────────────────
doc <- doc |>
  body_set_default_section(
    prop_section(
      page_size = page_size(width  = 8.27, height = 11.69, orient = "portrait"),
      page_margins = page_mar(
        top    = 0.98,   # 2,5 cm
        bottom = 0.98,
        left   = 0.98,
        right  = 0.98,
        header = 0.5,
        footer = 0.5
      )
    )
  )

# ── Salvar ────────────────────────────────────────────────────────────────────
dir.create(here::here("article"), showWarnings = FALSE, recursive = TRUE)
print(doc, target = out_path)

cat(sprintf("[OK] Arquivo gerado: %s\n", out_path))
cat("Agora execute: quarto render article/enaju-gcpj-article.qmd --to docx\n")
