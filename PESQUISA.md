# PESQUISA.md — Guia de Execução do Pipeline

**Projeto:** ENAJU-GCPJ — Mapeamento Bibliométrico Global  
**Periódico-alvo:** Revista de Administração Pública (RAP/FGV)  
**Última atualização:** 2025

---

## Visão geral do pipeline

O pipeline é composto por 16 scripts R executados sequencialmente, organizados em quatro fases:

```
Fase 1 — Coleta:       00 → 01 → 02 → 03 → 04 → 05
Fase 2 — Consolidação: 06 → 07
Fase 3 — Análise:      08 → 09 → 10 → 11 → 12 → 13 → 14
Fase 4 — Publicação:   99
```

Cada script implementa **cache automático**: se já foi executado com sucesso, reexecutá-lo carrega os dados salvos sem refazer a coleta. Isso permite retomar o pipeline a partir de qualquer ponto.

---

## Fase 0 — Configuração inicial (executar uma única vez)

### Passo 0.1 — Clonar o repositório

```bash
git clone https://github.com/SEU_USUARIO/enaju-gcpj.git
cd enaju-gcpj
```

### Passo 0.2 — Configurar credenciais

```bash
cp .env.example .env
```

Abra o arquivo `.env` e preencha:

| Variável | Onde obter | Obrigatoriedade |
|----------|-----------|-----------------|
| `SCOPUS_API_KEY` | [dev.elsevier.com](https://dev.elsevier.com) — conta institucional | **Obrigatória** |
| `SCOPUS_INST_TOKEN` | Solicitar à biblioteca institucional | Recomendada |
| `CROSSREF_EMAIL` | Qualquer email institucional válido | **Obrigatória** |
| `OPENALEX_EMAIL` | Qualquer email institucional válido | **Obrigatória** |
| `SEMANTIC_SCHOLAR_API_KEY` | [api.semanticscholar.org](https://api.semanticscholar.org) — registro gratuito | Recomendada |

**Importante:** o arquivo `.env` nunca deve ser commitado. Ele já está no `.gitignore`.

### Passo 0.3 — Verificar dependências de sistema

```r
# No R, verificar versão
R.version$version.string  # Deve ser ≥ 4.3.0

# Verificar Quarto
system("quarto --version")  # Deve ser ≥ 1.4
```

### Passo 0.4 — Executar o setup

```r
source("scripts/00_setup.R")
```

O script `00_setup.R` instalará todos os pacotes R necessários, validará as credenciais, criará a estrutura de diretórios (idempotente) e salvará o objeto `QUERIES` com as strings de busca dos quatro corpora.

**Saídas esperadas:**
- `[OK]` para cada credencial configurada
- `[OK]` para cada diretório criado ou já existente
- `[OK] Queries de busca definidas e salvas`
- Arquivo `data/processed/queries.rds`
- Arquivo `logs/pipeline_log.md` inicializado

---

## Fase 1 — Coleta de dados

> **Tempo estimado:** 2–6 horas no total, dependendo do volume de resultados e dos limites de rate das APIs.

### Passo 1.1 — Scopus

```r
source("scripts/01_collect_scopus.R")
```

Coleta via `rscopus` com paginação automática (25 registros/página, até 5.000 por corpus). Implementa retry automático em caso de falha de rede.

**Saídas:** `data/raw/corpus_{A,B,C,D}/scopus_raw_{A,B,C,D}.{rds,csv}`

**Atenção:** A API Scopus limita 20.000 requisições/semana por chave. Para o corpus completo (~20.000 registros esperados), a coleta pode precisar ser distribuída em dois dias se os limites forem atingidos.

### Passo 1.2 — OpenAlex

```r
source("scripts/02_collect_openalex.R")
```

Coleta via `openalexR::oa_fetch()`, sem limite de registros. O email configurado no `.env` habilita o polite pool, que oferece throughput superior.

**Saídas:** `data/raw/corpus_{A,B,C,D}/openalex_raw_{A,B,C,D}.{rds,csv}`

### Passo 1.3 — Semantic Scholar

```r
source("scripts/03_collect_semantic_scholar.R")
```

Coleta via API S2AG com paginação por offset. Sem chave: limite de 100 requisições/5 minutos. Com chave: 1 requisição/segundo.

**Saídas:** `data/raw/corpus_{A,B,C,D}/ss_raw_{A,B,C,D}.{rds,csv}`

### Passo 1.4 — Crossref

```r
source("scripts/04_collect_crossref.R")
```

Coleta via `rcrossref::cr_works()` com filtros de tipo (`journal-article`) e período (`from_pub_date=1995`).

**Saídas:** `data/raw/corpus_{A,B,C,D}/crossref_raw_{A,B,C,D}.{rds,csv}`

### Passo 1.5 — SciELO

```r
source("scripts/05_collect_scielo.R")
```

Coleta via SciELO Search API com fallback automático para scraping do portal SciELO.org via `rvest` caso a API falhe.

**Saídas:** `data/raw/corpus_{A,B,C,D}/scielo_raw_{A,B,C,D}.{rds,csv}`  
`data/raw/scielo/scielo_all_corpora.rds`

---

## Fase 2 — Consolidação e classificação

### Passo 2.1 — Merge e deduplicação

```r
source("scripts/06_merge_deduplicate.R")
```

Carrega todos os arquivos `.rds` de cada corpus, normaliza o esquema de colunas e realiza deduplicação em duas camadas: DOI exato (caso-insensível) e título normalizado. A prioridade de fonte é Scopus > OpenAlex > Crossref > Semantic Scholar > SciELO.

**Saídas:**
- `data/processed/corpus_{A,B,C,D}_merged.{rds,csv}` — corpus por grupo após dedup
- `data/processed/corpus_full.{rds,csv}` — corpus completo consolidado
- `data/processed/dedup_report.{rds,csv}` — relatório de deduplicação

**Verificar:** o relatório de deduplicação deve mostrar redução de 20–40% do total de registros brutos. Redução acima de 60% pode indicar queries muito similares entre corpora.

### Passo 2.2 — Classificação e PRISMA

```r
source("scripts/07_classify_corpora.R")
```

Aplica classificação automática baseada em dicionário de termos nucleares, filtra registros inelegíveis e gera o diagrama PRISMA 2020.

**Saídas:**
- `data/processed/corpus_classified.rds`
- `data/processed/corpus_eligible.{rds,csv}` — corpus final de análise
- `data/processed/prisma_stats.rds`
- `data/outputs/figures/prisma_flow.png`

**Revisão manual recomendada:** os registros classificados como `uncategorized` merecem revisão antes de serem descartados. Abrir `corpus_classified.rds` e filtrar `classification == "uncategorized"` para inspeção.

---

## Fase 3 — Análise bibliométrica

### Passo 3.1 — Análise descritiva (bibliometrix)

```r
source("scripts/08_bibliometric_analysis.R")
```

Gera análise descritiva completa: produção anual, por corpus, top periódicos, top países, Bradford. Produz figuras `fig01` a `fig05` e tabelas `tab01` a `tab03`.

### Passo 3.2 — Redes de cocitação

```r
source("scripts/09_cocitation_analysis.R")
```

Gera três redes: cocitação de referências (ACA), coautoria (componente gigante) e colaboração internacional. Detecção de comunidades via Louvain. Produz figuras `fig06` a `fig08` e tabela `tab04`.

### Passo 3.3 — Coocorrência de palavras-chave

```r
source("scripts/10_keyword_cooccurrence.R")
```

Gera rede de coocorrência, mapa temático Callon e evolução temporal. Produz figuras `fig09` a `fig13` e tabela `tab05`.

**Atenção:** `thematicEvolution()` do `bibliometrix` pode ser lento (10–20 min) para corpus grande. Não interromper.

### Passo 3.4 — Acoplamento bibliográfico

```r
source("scripts/11_bibliographic_coupling.R")
```

Acoplamento de artigos recentes (2015–2025) e de periódicos. Produz figuras `fig14` e `fig15` e tabelas `tab06` e `tab07`.

### Passo 3.5 — Modelagem de tópicos (LDA)

```r
source("scripts/12_topic_modeling.R")
```

Pré-processamento textual, DTM, seleção de k via `ldatuning` (4 métricas), LDA Gibbs (2.000 iterações). Produz figuras `fig16` a `fig18` e tabelas `tab08` a `tab10`.

**Tempo estimado:** 30–90 minutos dependendo do tamanho do corpus e do hardware.

**Após execução:** revisar os rótulos sugeridos em `data/outputs/tables/tab10_topic_labels.csv` e ajustar manualmente conforme interpretação substantiva dos tópicos.

### Passo 3.6 — Mapeamento institucional

```r
source("scripts/13_institutional_mapping.R")
```

Gera banco de dados de 35 instituições, mapa mundial de produção e relatório de gap do Corpus C. Produz figura `fig19` e tabelas `tab11` a `tab13`.

### Passo 3.7 — Índice IMECPJ

```r
source("scripts/14_maturity_index.R")
```

Calcula o Índice de Maturidade para 15 países e gera ranking, mapa de calor e radar Brasil vs. médias avançadas. Produz figuras `fig20` a `fig22` e tabela `tab14`.

**Importante:** os scores do IMECPJ são estimativas baseadas em proxy bibliométrico. Antes de submissão, revisar e ajustar os scores de `scores_raw` no script com base em relatórios institucionais adicionais disponíveis.

---

## Fase 4 — Geração do artigo

### Passo 4.1 — Renderizar o artigo

```r
source("scripts/99_render_article.R")
```

Verifica dependências, gera o documento de referência DOCX para o estilo RAP via `officer` e renderiza o artigo Quarto nos formatos HTML e DOCX.

**Saídas:**
- `article/enaju-gcpj-article.html` — versão HTML completa para revisão
- `article/enaju-gcpj-article.docx` — versão DOCX para submissão à RAP
- `data/outputs/enaju-gcpj-article.{html,docx}` — cópia na pasta de outputs

### Passo 4.2 — Revisar o artigo gerado

Antes de submeter à RAP, verificar:

1. **Contagens:** todos os valores estatísticos no texto (`n_total`, `n_judicial`, `pct_c`) foram calculados corretamente pelo corpus final.
2. **Figuras:** todas as 11 figuras referenciadas no texto estão presentes e com boa resolução (300 dpi).
3. **Tabelas:** as quatro tabelas/quadros estão completas e formatadas.
4. **Referências:** todas as citações têm entrada correspondente no `references.bib`; verificar se o estilo ABNT foi aplicado corretamente.
5. **Rótulos LDA:** os tópicos identificados no modelo receberam rótulos interpretativos adequados (revisar `tab10_topic_labels.csv` e atualizar o texto da seção 4.5).
6. **IMECPJ:** a nota de limitação sobre os scores estimados está presente e suficientemente explícita.

### Passo 4.3 — Preparar a submissão

A RAP aceita submissões pelo portal ScholarOne (Manuscriptlink). Documentos exigidos:

- Artigo completo em DOCX (sem identificação de autoria)
- Carta de apresentação
- Declaração de contribuição de autoria (CRediT)
- Dados de todos os autores (preenchidos no sistema, não no manuscrito)

Limite de palavras RAP: 8.000–10.000 palavras (excluindo resumo, referências e elementos pós-textuais).

---

## Versionamento e commits recomendados

Após cada fase concluída:

```bash
git add scripts/ article/
git commit -m "fase-1: coleta concluída — N registros brutos"

git add data/processed/ data/outputs/
git commit -m "fase-2: corpus elegível — N registros únicos"

git commit -m "fase-3: análise bibliométrica completa — N figuras, N tabelas"

git commit -m "fase-4: artigo renderizado — versão vX.Y"
```

Os diretórios `data/raw/`, `data/processed/` e `data/outputs/` estão no `.gitignore`. Versione apenas os scripts e o artigo.

---

## Solução de problemas frequentes

**`Error: SCOPUS_API_KEY not set`** — Verificar se o `.env` foi criado e preenchido. Reexecutar `00_setup.R`.

**`biblioNetwork: CR column not found`** — O objeto M não foi construído corretamente a partir dos arquivos Scopus CSV. Verificar se `01_collect_scopus.R` gerou arquivos `.csv` válidos e se o `bibliometrix::convert2df()` os leu sem erros.

**`thematicMap: not enough keywords`** — O campo `DE` do objeto M está vazio. Verificar se a coleta Scopus incluiu a coluna de palavras-chave e se `convert2df()` a mapeou corretamente.

**Renderização DOCX falha com erro de pandoc** — Verificar se `rap_reference.docx` foi gerado por `99_render_article.R` antes da renderização. Reexecutar o passo de geração do template.

**`ldatuning` muito lento** — Reduzir `k_range` de `4:14` para `5:10` no script `12_topic_modeling.R`. O modelo LDA pode ser treinado diretamente com `k = 8` se a seleção automática não for prioritária.
