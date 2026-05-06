# enaju-gcpj

**Mapeamento Bibliométrico Global da Educação Corporativa Pública e Judiciária**

Este repositório contém o pipeline completo de coleta, processamento e análise bibliométrica para o artigo científico submetido à *Revista de Administração Pública* (RAP/FGV). O estudo mapeia a produção científica global sobre desenvolvimento de capacidades institucionais em organizações públicas e judiciárias, cobrindo o período 1995–2025.

---

## Estrutura do repositório

```
enaju-gcpj/
├── .env.example          # Modelo de variáveis de ambiente (copie para .env)
├── _quarto.yml           # Configuração global do projeto Quarto
├── scripts/
│   ├── 00_setup.R        # Configuração do ambiente e definição das queries
│   ├── 01_collect_scopus.R
│   ├── 02_collect_openalex.R
│   ├── 03_collect_semantic_scholar.R
│   ├── 04_collect_crossref.R
│   ├── 05_collect_scielo.R
│   ├── 06_merge_deduplicate.R
│   ├── 07_classify_corpora.R
│   ├── 08_bibliometric_analysis.R
│   ├── 09_cocitation_analysis.R
│   ├── 10_keyword_cooccurrence.R
│   ├── 11_bibliographic_coupling.R
│   ├── 12_topic_modeling.R
│   ├── 13_institutional_mapping.R
│   ├── 14_maturity_index.R
│   └── 99_render_article.R
├── article/
│   ├── enaju-gcpj-article.qmd   # Artigo principal (Quarto)
│   └── references.bib           # Referências bibliográficas (BibTeX)
├── data/
│   ├── raw/              # Dados brutos por corpus e fonte (não versionado)
│   ├── processed/        # Objetos R processados (não versionado)
│   └── outputs/
│       ├── figures/      # Todas as figuras geradas
│       ├── tables/       # Tabelas em CSV
│       └── networks/     # Objetos igraph das redes
└── logs/
    └── pipeline_log.md   # Registro de execução do pipeline
```

---

## Corpora temáticos

O corpus foi estruturado em quatro grupos temáticos complementares:

| Corpus | Campo temático | Bases de coleta |
|--------|---------------|-----------------|
| **A** | Educação corporativa e aprendizagem organizacional | Scopus, OpenAlex, Crossref, SS, SciELO |
| **B** | Setor público e desenvolvimento de capacidades | Scopus, OpenAlex, Crossref, SS, SciELO |
| **C** | Educação judiciária | Scopus, OpenAlex, Crossref, SS, SciELO |
| **D** | Inovação, tecnologia e avaliação educacional | Scopus, OpenAlex, Crossref, SS, SciELO |

---

## Pré-requisitos

- R ≥ 4.3.0
- Quarto ≥ 1.4
- Chave de API Scopus (obrigatória)
- Email para polite pool OpenAlex e Crossref (obrigatório)
- Chave Semantic Scholar (opcional, mas recomendada para evitar throttling)

Consulte o `PESQUISA.md` para o passo a passo completo de execução.

---

## Execução rápida

```r
# 1. Configurar credenciais
file.copy(".env.example", ".env")
# Edite o .env com suas chaves antes de continuar

# 2. Executar o pipeline sequencialmente
source("scripts/00_setup.R")     # Ambiente e queries
source("scripts/01_collect_scopus.R")
source("scripts/02_collect_openalex.R")
source("scripts/03_collect_semantic_scholar.R")
source("scripts/04_collect_crossref.R")
source("scripts/05_collect_scielo.R")
source("scripts/06_merge_deduplicate.R")
source("scripts/07_classify_corpora.R")
source("scripts/08_bibliometric_analysis.R")
source("scripts/09_cocitation_analysis.R")
source("scripts/10_keyword_cooccurrence.R")
source("scripts/11_bibliographic_coupling.R")
source("scripts/12_topic_modeling.R")
source("scripts/13_institutional_mapping.R")
source("scripts/14_maturity_index.R")
source("scripts/99_render_article.R")
```

O artigo final será gerado em `article/enaju-gcpj-article.html` e `article/enaju-gcpj-article.docx`.

---

## Reprodutibilidade

Todos os scripts implementam cache por `.rds` — se um script já foi executado com sucesso, reexecutá-lo carrega o cache sem refazer a coleta. Isso permite reiniciar o pipeline a partir de qualquer ponto sem perder dados já coletados.

O pipeline gera automaticamente um log de execução em `logs/pipeline_log.md` com timestamps, contagens e alertas.

---

## Execução pelo GitHub Actions

O repositório inclui dois workflows que permitem executar todo o pipeline a
partir da interface do GitHub, sem necessidade de máquina local.

### Secrets necessários

Em **Settings → Secrets and variables → Actions**, configure:

| Secret | Status | Uso |
|---|---|---|
| `SCOPUS_API_KEY` | obrigatório p/ Scopus | autenticação `rscopus` |
| `SCOPUS_INST_TOKEN` | opcional | Scopus institucional |
| `OPENALEX_EMAIL` | recomendado | polite pool OpenAlex |
| `CROSSREF_EMAIL` | recomendado | polite pool Crossref |
| `SEMANTIC_SCHOLAR_API_KEY` | opcional | evita HTTP 429 no SS |
| `SCIELO_EMAIL` | opcional | reservado |

Nada é versionado: o `.gitignore` bloqueia `.env` e `data/`; nos workflows
os secrets são injetados via `env:` e nunca aparecem nos logs.

### 1. Workflow `Collect bibliometric data` (`.github/workflows/collect.yml`)

Roda os scripts `01–05` (coleta) com cache de pacotes R.

1. **Actions → Collect bibliometric data → Run workflow**.
2. Inputs:
   - `sources` — coletas a executar, separadas por vírgula. Default: `openalex,crossref,semantic_scholar,scielo`. Use `scopus,openalex,semantic_scholar,crossref,scielo` para incluir Scopus.
   - `openalex_max` (default `5000`) — máx. de registros por corpus no OpenAlex.
   - `crossref_max` (default `2000`) — máx. de registros por corpus no Crossref.
   - `r_version` (default `4.4.1`).
3. Artifacts gerados (retenção 14 dias):
   - `enaju-raw-data` → `data/raw/**`
   - `enaju-processed-data` → `data/processed/**` (queries, etc.)
   - `enaju-logs` → `logs/**`

### 2. Workflow `Run bibliometric pipeline` (`.github/workflows/pipeline.yml`)

Roda os scripts `06–14` (merge, deduplicação, análises bibliométricas) e,
opcionalmente, `99` (renderização Quarto do artigo).

1. **Actions → Run bibliometric pipeline → Run workflow**.
2. Inputs:
   - `from_step` — script inicial (ex.: `06`, `08`).
   - `run_render` — `true` para renderizar o artigo ao final.
   - `raw_artifact_run_id` (opcional) — Run ID do `Collect bibliometric data` para baixar `data/raw/**` antes de rodar.
   - `processed_artifact_run_id` (opcional) — idem para `data/processed/**`.
   - `r_version` (default `4.4.1`).
3. Artifacts gerados:
   - `enaju-processed-data` (14 dias)
   - `enaju-outputs` → figuras, tabelas, redes (30 dias)
   - `enaju-article` → HTML/DOCX/PDF do artigo, se renderizado (30 dias)
   - `enaju-logs` (14 dias)

### Fluxo recomendado (100% no GitHub)

1. Disparar `Collect bibliometric data` → aguardar conclusão.
2. Anotar o **Run ID** desse run (URL termina em `.../runs/<ID>`).
3. Disparar `Run bibliometric pipeline` informando esse Run ID em `raw_artifact_run_id` e (se quiser renderizar) `run_render=true`.
4. Baixar `enaju-outputs` e `enaju-article` ao final.

### Como baixar artifacts

Na página do run concluído, role até a seção **Artifacts** e clique no nome do
artifact desejado para baixar um `.zip`. Também é possível usar o `gh` CLI:

```bash
gh run download <RUN_ID> -n enaju-raw-data -D ./data/raw
gh run download <RUN_ID> -n enaju-outputs   -D ./data/outputs
```

### Variáveis de ambiente reconhecidas pelos scripts

| Variável | Função | Default |
|---|---|---|
| `ENAJU_PHASE` | `collection` instala apenas pacotes da fase de coleta; `analysis` instala tudo. | `all` |
| `ENAJU_OPENALEX_MAX` | Máx. registros por corpus em `02_collect_openalex.R` | `5000` |
| `ENAJU_CROSSREF_MAX` | Máx. registros por corpus em `04_collect_crossref.R` | `2000` |

---

## Licença

Código sob licença MIT. Dados coletados das bases respeitam os termos de uso de cada provedor.

---

## Citação

> MACHADO, Igor Caires. *Educação Corporativa Pública e Judiciária: um mapeamento bibliométrico global do desenvolvimento de capacidades institucionais*. Submetido à Revista de Administração Pública, 2025.
