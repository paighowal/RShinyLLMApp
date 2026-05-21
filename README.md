# Clinical Trial LLM Assistant

A Shiny app that lets you query clinical trial data in plain English. Type a question, and the app generates SQL, runs it against the database, and returns the results as a chart, map, or table.

Built on top of [AACT data from ClinicalTrials.gov](https://aact.ctti-clinicaltrials.org/).
## Sample screenshot of AI powered RShiny Chatbot
<img width="1911" height="1136" alt="image" src="https://github.com/user-attachments/assets/4bb138d7-8c51-4eb1-9dfb-4a13402e01ac" />

## Sample screenshot
<img width="1911" height="914" alt="image" src="https://github.com/user-attachments/assets/d9462b75-e00c-459d-8e5b-2b9a7df47409" />

---

## What it does

You type something like *"top 10 sponsors by enrollment"* or *"map Novartis sites in Europe"* and the app:

1. Sends your question to an LLM (Groq or OpenAI) to generate a SQL query
2. Runs that query against an in-memory SQLite database
3. Displays the results — bar chart, histogram, or leaflet map depending on the data
4. Shows the SQL it used so you can verify or tweak it

You can switch between Groq (LLaMA-3.3-70B) and OpenAI (GPT-4o-mini) from the sidebar. The app defaults to Groq.

---

## Data

Two pipe-delimited CSV files loaded at startup:

- **`aact_multiple_sponsors.csv`** — trial metadata: sponsor, phase, status, enrollment, conditions, outcomes, dates
- **`aact_facilities.csv`** — site locations: name, city, state, country, lat/lon

Both tables join on `nct_id`. Download them from the [AACT snapshot page](https://aact.ctti-clinicaltrials.org/snapshots).

---

## Setup

**Install packages**

```r
install.packages(c(
  "shiny", "shinydashboard", "shinychat", "DT", "plotly",
  "dplyr", "DBI", "RSQLite", "httr", "jsonlite", "text2vec",
  "stringr", "readr", "leaflet", "sf", "shinyjs"
))
```

**Set API keys**

Open `~/.Renviron` (`usethis::edit_r_environ()`) and add:

```
GROQ_API_KEY=gsk_...
OPENAI_API_KEY=sk-...        # optional
HUGGINGFACE_API_KEY=hf_...   # optional, for embeddings
```

Restart R after saving. At minimum you need one of `GROQ_API_KEY` or `OPENAI_API_KEY`.

Get a free Groq key at [console.groq.com](https://console.groq.com/).

**Set the data path**

Update `FILE_PATH` in `app.R` to point to the folder with your CSV files:

```r
FILE_PATH <- "path/to/your/data/"
```

**Run**

```r
shiny::runApp("path/to/RShinyChatBot")
```

---

## Example questions

- *"What is the distribution of studies by phase?"*
- *"Top 10 sponsors by total enrollment"*
- *"How many trials are currently recruiting?"*
- *"Map all Pfizer trial sites"*
- *"Average enrollment for Phase 3 oncology trials"*
- *"How many studies started in 2022?"*
- *"Which countries have the most facilities?"*

---

## Changing the model

The Groq model is set near the top of `app.R`:

```r
GROQ_MODEL <- "llama-3.3-70b-versatile"   # default
# GROQ_MODEL <- "llama-3.1-8b-instant"    # faster
# GROQ_MODEL <- "mixtral-8x7b-32768"      # longer context
```

---

## Troubleshooting

**App won't start** — make sure at least one API key is set in `.Renviron` and you've restarted R.

**SQL error in chat** — try rephrasing the question more specifically. Mentioning column names (e.g. "study phase" vs "phase") usually helps.

**Map shows nothing** — the query result may not have lat/lon values. Try filtering to a specific sponsor or country first.

**Slow responses** — switch to `llama-3.1-8b-instant` for faster turnaround at the cost of some quality.

---

## Stack

R Shiny, shinydashboard, Groq / OpenAI, SQLite, Plotly, Leaflet, httr, dplyr

---

## License

MIT
