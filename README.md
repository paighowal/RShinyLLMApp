# 🧬 Clinical Trial LLM Assistant

> An intelligent R Shiny chatbot for exploring clinical trial data using plain English.  
> Ask natural language questions → get SQL-powered results as interactive charts, maps, and tables.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [App Screenshots](#app-screenshots)
- [Tech Stack](#tech-stack)
- [Data](#data)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the App](#running-the-app)
- [Usage Examples](#usage-examples)
- [App Architecture](#app-architecture)
- [Project Structure](#project-structure)
- [API Keys](#api-keys)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

The **Clinical Trial LLM Assistant** is a conversational data exploration tool built with R Shiny. It connects to a clinical trials database (sourced from [AACT / ClinicalTrials.gov](https://aact.ctti-clinicaltrials.org/)) and allows users to ask questions in plain English.

Under the hood, a Large Language Model (LLM) — either **Groq (LLaMA-3.3-70B)** or **OpenAI (GPT-4o-mini)** — translates each question into a SQL query, executes it against an in-memory SQLite database, and returns the results with automated visualizations and key insights.

---

## Features

| Feature | Description |
|---------|-------------|
| 💬 **Natural Language Chat** | Ask questions in plain English — no SQL knowledge needed |
| 🤖 **Dual LLM Support** | Switch between Groq (LLaMA-3.3-70B) and OpenAI (GPT-4o-mini) from the sidebar |
| 🗺️ **Interactive Maps** | Geographic visualizations of trial sites with marker clustering using Leaflet |
| 📊 **Auto Visualizations** | Bar charts and histograms auto-generated based on query results via Plotly |
| 📋 **Data Tables** | Paginated, searchable result tables with column sorting |
| 🔍 **Data Explorer** | Browse raw sponsors and facilities tables directly |
| ⬇️ **CSV Export** | Download any query result as a CSV file |
| ⌨️ **Keyboard Shortcut** | Press Enter to submit queries (no mouse needed) |
| 🔄 **SQL Transparency** | View the exact SQL query generated for every question |

---

## App Screenshots

> _Add screenshots here after deployment_

| Chat Interface | Map View | Data Explorer |
|----------------|----------|---------------|
| _(screenshot)_ | _(screenshot)_ | _(screenshot)_ |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI Framework** | R Shiny + shinydashboard |
| **LLM — Primary** | [Groq](https://groq.com/) — LLaMA-3.3-70B (free tier available) |
| **LLM — Alternate** | [OpenAI](https://openai.com/) — GPT-4o-mini |
| **Database** | SQLite in-memory via RSQLite + DBI |
| **Charts** | Plotly (interactive bar charts, histograms) |
| **Maps** | Leaflet (marker clustering, OpenStreetMap tiles) |
| **Embeddings** | HuggingFace Inference API — `sentence-transformers/all-MiniLM-L6-v2` |
| **HTTP Requests** | httr |
| **Data Wrangling** | dplyr, readr, stringr |
| **Spatial** | sf |

---

## Data

The app loads two pipe-delimited (`|`) CSV files from the AACT database into an in-memory SQLite database at startup.

### Tables

#### `aact_multiple_sponsors` — Clinical Trial Metadata
Key columns include:

| Column | Description |
|--------|-------------|
| `nct_id` | Unique ClinicalTrials.gov identifier (e.g. NCT01234567) |
| `sponsor_name` | Name of the sponsoring organization |
| `study_phase` | Trial phase (Phase 1, Phase 2, Phase 3, etc.) |
| `study_status` | Current status (Recruiting, Completed, etc.) |
| `enrollment` | Number of participants |
| `disease_condition` | Medical condition(s) being studied |
| `start_date` / `primary_completion_date` | Study timeline dates |
| `study_type` | Interventional or Observational |
| `is_fda_regulated_drug` / `is_fda_regulated_device` | Regulatory flags |
| `were_results_reported` | Whether results were submitted |

#### `facilities` — Trial Site Locations
Key columns include:

| Column | Description |
|--------|-------------|
| `nct_id` | Links to the sponsors table |
| `site_name` | Name of the facility/institution |
| `site_status` | Recruiting, Active, Suspended, etc. |
| `city`, `state`, `country` | Geographic location |
| `latitude`, `longitude` | Coordinates (used for map visualizations) |

Both tables are joined via the `nct_id` column.

### Data Source

Download data from the [AACT database](https://aact.ctti-clinicaltrials.org/snapshots).  
Place the files in a folder and update `FILE_PATH` in `app.R`.

---

## Prerequisites

- **R** ≥ 4.1.0
- **RStudio** (recommended)
- At least one LLM API key:
  - [Groq API key](https://console.groq.com/) — free tier available, fast inference
  - [OpenAI API key](https://platform.openai.com/) — requires billing
- _(Optional)_ [HuggingFace API key](https://huggingface.co/settings/tokens) — for embeddings

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/your-username/RShinyChatBot.git
cd RShinyChatBot
```

### 2. Install required R packages

Open R or RStudio and run:

```r
install.packages(c(
  "shiny",
  "shinydashboard",
  "shinychat",
  "DT",
  "plotly",
  "dplyr",
  "DBI",
  "RSQLite",
  "httr",
  "jsonlite",
  "text2vec",
  "stringr",
  "readr",
  "leaflet",
  "sf",
  "shinyjs"
))
```

---

## Configuration

### 1. Set API keys

Open your `.Renviron` file:

```r
usethis::edit_r_environ()
```

Add your keys:

```
GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
HUGGINGFACE_API_KEY=hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Save and restart R (`Ctrl+Shift+F10` in RStudio).

> **Minimum requirement:** At least `GROQ_API_KEY` **or** `OPENAI_API_KEY` must be set.  
> The app defaults to Groq if `GROQ_API_KEY` is present.

### 2. Set the data file path

In `app.R`, update `FILE_PATH` to point to the folder containing your CSV files:

```r
FILE_PATH <- "path/to/your/knowledge-base/"
```

### 3. (Optional) Change the LLM model

```r
# Groq model options
GROQ_MODEL <- "llama-3.3-70b-versatile"   # default (recommended)
# GROQ_MODEL <- "llama-3.1-8b-instant"    # faster, lighter
# GROQ_MODEL <- "mixtral-8x7b-32768"      # longer context window

# OpenAI model
LLM_MODEL <- "gpt-4o-mini"
```

---

## Running the App

```r
shiny::runApp("path/to/RShinyChatBot")
```

Or open `app.R` in RStudio and click **Run App**.

The app will:
1. Load both CSV files into an in-memory SQLite database
2. Start the Shiny server
3. Open in your browser at `http://127.0.0.1:<port>`

---

## Usage Examples

Type any of these into the chat box:

**Enrollment & Sponsors**
- *"Who are the top 10 sponsors by total enrollment?"*
- *"Show me the average enrollment by study phase"*
- *"How many studies does Pfizer have?"*

**Study Status & Phase**
- *"What is the distribution of studies by phase?"*
- *"How many studies are currently recruiting?"*
- *"Show completed vs ongoing trials by year"*

**Geographic**
- *"Map all Novartis trial sites"*
- *"Which countries have the most trial facilities?"*
- *"Show recruiting sites in the United States"*

**Disease & Conditions**
- *"How many oncology trials are in Phase 3?"*
- *"List studies for diabetes with more than 1000 participants"*

**Dates & Timelines**
- *"How many trials started in 2022?"*
- *"What is the average time to report results?"*

---

## App Architecture

```
User Question
      │
      ▼
 LLM (Groq / OpenAI)
 SQL Generation Prompt
      │
      ▼
  SQL Query
 (extracted + cleaned)
      │
      ▼
 SQLite (in-memory)
 aact_multiple_sponsors
     + facilities
      │
      ▼
  Query Results
      │
      ├──► Plotly Chart (bar / histogram)
      ├──► Leaflet Map (if lat/lon present)
      ├──► DT Data Table
      └──► Chat Response + SQL display
```

---

## Project Structure

```
RShinyChatBot/
├── app.R          # Full application — UI, server, LLM calls, SQL, visualizations
└── README.md      # This file
```

All logic lives in a single `app.R` file, organized into clearly labeled sections:

| Section | Purpose |
|---------|---------|
| Configuration & Setup | Constants, API keys, model selection |
| Database Setup | Load CSVs → SQLite |
| LLM API Functions | `call_groq_api()`, `call_openai_api()`, `call_llm_api()` dispatcher |
| Vector DB & Embeddings | HuggingFace embedding calls |
| Database Schema Info | Schema context injected into LLM prompts |
| SQL Generation | Prompt engineering → SQL extraction |
| Query Execution | Run SQL against SQLite |
| Visualization | Auto-select chart type or map |
| Insight Generation | LLM-generated data summaries |
| Main Processing | `process_user_query()` orchestrator |
| Shiny UI | Dashboard layout |
| Shiny Server | Reactive logic, event handlers |

---

## API Keys

| Key | Where to get it | Required |
|-----|----------------|----------|
| `GROQ_API_KEY` | [console.groq.com](https://console.groq.com/) | ✅ Recommended (free) |
| `OPENAI_API_KEY` | [platform.openai.com](https://platform.openai.com/) | ⚡ Optional |
| `HUGGINGFACE_API_KEY` | [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) | ⚡ Optional (embeddings) |

---

## Troubleshooting

**App fails to start — "Please set at least one API key"**  
→ Check your `.Renviron` file has `GROQ_API_KEY` or `OPENAI_API_KEY` set, and restart R.

**"SQL Error" in the chat**  
→ The LLM may have misunderstood the question. Try rephrasing with more specific column names (e.g. "study phase" instead of just "phase").

**Map shows no markers**  
→ The query results may have missing lat/lon values. Try asking about a specific country or sponsor to narrow the data.

**Slow responses**  
→ Switch to `llama-3.1-8b-instant` in `GROQ_MODEL` for faster (but less capable) responses.

**Data not loading**  
→ Verify `FILE_PATH` points to the correct folder and both CSV files exist with the expected names (`aact_multiple_sponsors.csv` and `aact_facilities.csv`).

---

## License

MIT License — feel free to use, modify, and distribute with attribution.

---

_Built with R Shiny · Powered by Groq LLaMA & OpenAI · Data from ClinicalTrials.gov (AACT)_
