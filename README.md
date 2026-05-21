# Clinical Trial LLM Assistant

An R Shiny chatbot that lets you explore clinical trial data using plain English.
Ask questions in natural language — the app converts them to SQL, runs the query,
and returns results as interactive charts, maps, or tables.

![R](https://img.shields.io/badge/R-4.5%2B-blue) ![Shiny](https://img.shields.io/badge/Shiny-dashboard-brightgreen) ![LLM](https://img.shields.io/badge/LLM-Groq%20%7C%20OpenAI-orange)

---

## Features

- **Natural language → SQL** — powered by Groq (LLaMA-3.3-70B) or OpenAI (GPT-4o-mini)
- **Interactive visualizations** — bar charts and histograms via Plotly
- **Geographic maps** — site-level leaflet maps with marker clustering
- **Data explorer** — browse raw sponsors and facilities tables
- **Downloadable results** — export any query result as CSV
- **Provider switcher** — toggle between Groq and OpenAI from the sidebar

---

## Data

The app expects two pipe-delimited (`|`) CSV files in the knowledge base folder:

| File | Description |
|------|-------------|
| `aact_multiple_sponsors.csv` | Clinical trial metadata (sponsor, phase, enrollment, outcomes, etc.) |
| `aact_facilities.csv` | Trial site locations (name, city, state, country, lat/lon) |

Both tables are linked by `nct_id`. Data is sourced from
[AACT (ClinicalTrials.gov)](https://aact.ctti-clinicaltrials.org/).

---

## Setup

### 1. Install R packages

```r
install.packages(c(
  "shiny", "shinydashboard", "shinychat", "DT", "plotly",
  "dplyr", "DBI", "RSQLite", "httr", "jsonlite", "text2vec",
  "stringr", "readr", "leaflet", "sf", "shinyjs"
))
