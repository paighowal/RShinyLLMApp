# R Shiny LLM Chatbot with RAG Framework
# Libraries
library(shiny)
library(shinydashboard)
library(shinychat)
library(DT)
library(plotly)
library(dplyr)
library(DBI)
library(RSQLite)
library(httr)
library(jsonlite)
library(text2vec)
#library(faiss)
library(stringr)
library(readr)
library(leaflet)
library(sf)
library(shinyjs)

# ================================
# CONFIGURATION & SETUP
# ================================

# Constants
EMBEDDING_MODEL <- "sentence-transformers/all-MiniLM-L6-v2"
LLM_MODEL <- "gpt-4o-mini"
GROQ_MODEL  <- "llama-3.3-70b-versatile"   # or "mixtral-8x7b-32768", "llama-3.1-8b-instant"
FILE_PATH <- "G:/My Drive/python/llm/udemy_llm/llm_engineering/cte/knowledge-base/"

# Environment variables (set these in your R environment)
OPENAI_API_KEY     <- Sys.getenv("OPENAI_API_KEY")
HUGGINGFACE_API_KEY <- Sys.getenv("HUGGINGFACE_API_KEY")
GROQ_API_KEY       <- Sys.getenv("GROQ_API_KEY")

if (OPENAI_API_KEY == "" && GROQ_API_KEY == "") {
  stop("Please set at least one of OPENAI_API_KEY or GROQ_API_KEY environment variables")
}
if (HUGGINGFACE_API_KEY == "") {
  warning("HUGGINGFACE_API_KEY not set — embeddings will be unavailable")
}

# ================================
# DATABASE SETUP
# ================================

# Create SQLite connection
con <- dbConnect(RSQLite::SQLite(), ":memory:")

# Load data (adjust paths as needed)
load_clinical_data <- function(file_path) {
  tryCatch({
    # Check if files exist first
    sponsors_file <- "aact_multiple_sponsors.csv"
    facilities_file <- "aact_facilities.csv"
    
    
    # Load data files
    sponsors_df <- read_delim(paste0(file_path, sponsors_file), 
                              delim = "|", 
                              quote = "\"",
                              locale = locale(encoding = "UTF-8"))
    
    facilities_df <- read_delim(paste0(file_path, facilities_file), 
                                delim = "|", 
                                quote = "\"", 
                                locale = locale(encoding = "UTF-8"))
    
    
    # Write to database
    dbWriteTable(con, "aact_multiple_sponsors", sponsors_df, overwrite = TRUE)
    dbWriteTable(con, "facilities", facilities_df, overwrite = TRUE)
    
    message("✅ Data loaded successfully!")
    message("   - Sponsors table: ", nrow(sponsors_df), " rows")
    message("   - Facilities table: ", nrow(facilities_df), " rows")
    
    return(list(sponsors = sponsors_df, facilities = facilities_df))
  }, error = function(e) {
    message("Error loading data: ", e$message)
    return(NULL)
  })
}

# Initialize data
clinical_data <- load_clinical_data(FILE_PATH)

# ================================
# LLM API FUNCTIONS
# ================================

# ------ shared helper: parse OpenAI-compatible chat response ------
.parse_chat_response <- function(response, provider_label) {
  if (status_code(response) == 200) {
    response_text <- content(response, "text", encoding = "UTF-8")
    cat("Raw", provider_label, "Response:\n", substr(response_text, 1, 500), "\n")
    parsed <- fromJSON(response_text, simplifyVector = FALSE)
    if (is.list(parsed) && "choices" %in% names(parsed) &&
        length(parsed$choices) > 0) {
      choice <- parsed$choices[[1]]
      if (is.list(choice) && "message" %in% names(choice)) {
        msg <- choice$message
        if (is.list(msg) && "content" %in% names(msg)) return(msg$content)
      }
    }
    return(paste("Unexpected API response structure:", substr(response_text, 1, 200)))
  } else {
    error_content <- content(response, "text")
    return(paste(provider_label, "API Error [", status_code(response), "]:", error_content))
  }
}

# OpenAI API call function
call_openai_api <- function(prompt, temperature = 0.3, max_tokens = 1000) {
  tryCatch({
    response <- POST(
      url = "https://api.openai.com/v1/chat/completions",
      add_headers(
        "Authorization" = paste("Bearer", OPENAI_API_KEY),
        "Content-Type" = "application/json"
      ),
      body = toJSON(list(
        model = LLM_MODEL,
        messages = list(list(role = "user", content = prompt)),
        temperature = temperature,
        max_tokens = max_tokens
      ), auto_unbox = TRUE),
      encode = "json"
    )
    .parse_chat_response(response, "OpenAI")
  }, error = function(e) {
    paste("Error calling OpenAI API:", e$message)
  })
}

# Groq API call function (OpenAI-compatible endpoint)
call_groq_api <- function(prompt, temperature = 0.3, max_tokens = 1000) {
  tryCatch({
    response <- POST(
      url = "https://api.groq.com/openai/v1/chat/completions",
      add_headers(
        "Authorization" = paste("Bearer", GROQ_API_KEY),
        "Content-Type" = "application/json"
      ),
      body = toJSON(list(
        model = GROQ_MODEL,
        messages = list(list(role = "user", content = prompt)),
        temperature = temperature,
        max_tokens = max_tokens
      ), auto_unbox = TRUE),
      encode = "json"
    )
    .parse_chat_response(response, "Groq")
  }, error = function(e) {
    paste("Error calling Groq API:", e$message)
  })
}

# Unified dispatcher — call with provider = "openai" | "groq"
call_llm_api <- function(prompt, temperature = 0.3, max_tokens = 1000,
                         provider = "openai") {
  if (provider == "groq") {
    call_groq_api(prompt, temperature, max_tokens)
  } else {
    call_openai_api(prompt, temperature, max_tokens)
  }
}

# ================================
# VECTOR DATABASE & EMBEDDINGS
# ================================

# Create embeddings using HuggingFace API
create_embeddings <- function(texts) {
  tryCatch({
    # Ensure texts is a vector
    if (is.character(texts) && length(texts) == 1) {
      input_data <- list(inputs = texts)
    } else {
      input_data <- list(inputs = as.list(texts))
    }
    
    response <- POST(
      url = paste0("https://api-inference.huggingface.co/models/", EMBEDDING_MODEL),
      add_headers(
        "Authorization" = paste("Bearer", HUGGINGFACE_API_KEY),
        "Content-Type" = "application/json"
      ),
      body = toJSON(input_data, auto_unbox = TRUE),
      encode = "json"
    )
    
    if (status_code(response) == 200) {
      response_text <- content(response, "text", encoding = "UTF-8")
      embeddings <- fromJSON(response_text, simplifyVector = TRUE)
      return(embeddings)
    } else {
      error_content <- content(response, "text")
      cat("HuggingFace API Error [", status_code(response), "]:", error_content, "\n")
      return(NULL)
    }
  }, error = function(e) {
    message("Error creating embeddings: ", e$message)
    return(NULL)
  })
}

# ================================
# DATABASE SCHEMA INFORMATION
# ================================

get_schema_info <- function() {
  schema_context <- "
  DATABASE SCHEMA:
  
  TABLE 1: aact_multiple_sponsors
   -  studyid :  Unique internal identifier for each clinical study
   -  sponsor_name :  Name of the organization or individual sponsoring the study
   -  nct_id :  A unique identifier assigned by ClinicalTrials.gov for each clinical trial, used to link related information across different tables (eg, NCT01234567)
   -  start_date_type :  Indicates whether the start date is actual or anticipated
   -  start_date :  Date when the study began or is expected to begin
   -  primary_completion_date :  Date when data collection for the primary outcome is completed
   -  target_duration :  Planned duration of the study (eg, in months or years)
   -  study_type :  Type of study (eg, Interventional, Observational)
   -  acronym :  Short abbreviation or acronym for the study title
   -  brief_title :  Concise title of the study used for public display
   -  official_title :  Full formal title of the study
   -  study_status :  Current status of the study (eg, Recruiting, Completed)
   -  study_phase :  Phase of the clinical trial (eg, Phase 1, Phase 3)
   -  enrollment :  Number of participants enrolled in the study
   -  enrollment_type :  Type of enrollment (eg, Actual or Anticipated)
   -  number_of_arms :  Number of arms or treatment groups in the study
   -  number_of_groups :  Number of distinct participant groups (may differ from arms)
   -  has_expanded_access :  Indicates if the study offers expanded access to investigational products
   -  has_dmc :  Whether the study has a Data Monitoring Committee (DMC)
   -  is_fda_regulated_drug :  Indicates if the study involves an FDA-regulated drug
   -  is_fda_regulated_device :  Indicates if the study involves an FDA-regulated device
   -  is_unapproved_device :  Whether the study involves an unapproved device
   -  patient_registry :  Indicates if the study is a patient registry
   -  disease_condition :  Medical condition(s) being studied
   -  outcome_primary :  Description of the primary outcome measures
   -  outcome_secondary :  Description of the secondary outcome measures
   -  outcome_other :  Description of any other outcome measures
   -  number_of_facilities :  Number of clinical sites or facilities involved in the study
   -  number_of_nsae_subjects :  Number of subjects who experienced non-serious adverse events
   -  number_of_sae_subjects :  Number of subjects who experienced serious adverse events
   -  registered_in_calendar_year :  Year the study was registered on ClinicalTrialsgov
   -  actual_duration :  Actual duration of the study from start to completion
   -  were_results_reported :  Indicates whether study results were reported
   -  months_to_report_results :  Time taken (in months) to report results after study completion
   -  minimum_age_num :  Minimum age of participants (numeric value)
   -  maximum_age_num :  Maximum age of participants (numeric value)
   -  minimum_age_unit :  Unit for minimum age (eg, Years, Months)
   -  maximum_age_unit :  Unit for maximum age (eg, Years, Months)
   -  number_of_primary_outcomes_to_measure :  Count of primary outcomes being measured
   -  number_of_secondary_outcomes_to_measure :  Count of secondary outcomes being measured
   -  number_of_other_outcomes_to_measure :  Count of other outcomes being measured

  
  TABLE 2: facilities
   -  nct_id :  Unique identifier for the clinical trial, linking each site to its parent study
   -  site_name :  Name of the facility or institution conducting the trial (eg, hospital, university)
   -  site_status :  Operational status of the site (eg, Recruiting, Active, Suspended)
   -  city :  City where the clinical trial site is located
   -  state :  State or province of the site (primarily used for US locations)
   -  postal_code :  ZIP or postal code of the site's location
   -  country :  Country in which the site is located
   -  latitude :  Geographic latitude coordinate of the site, useful for mapping
   -  longitude :  Geographic longitude coordinate of the site, useful for mapping

  
  RELATIONSHIPS:
  - Both tables connected via 'nct_id' column
  - Use JOIN operations to combine trial and location data
  
  SEMANTIC MAPPINGS - Use these to understand user intent:
  - 'clinical trials', 'studies', 'trials' → refer to rows in aact_multiple_sponsors table
  - 'sites', 'facilities', 'clinical sites', 'locations' → refer to rows in facilities table
  - 'enrollment', 'participants', 'subjects', 'patients' → enrollment column in aact_multiple_sponsors
  - 'study id', 'study identifier' → refers to studyid or study number
  - 'trial id', 'nct identifier', 'nct number' → nct_id column (common in both tables)
  - 'phase', 'trial phase', 'study phase' → phase column in aact_multiple_sponsors
  - 'sponsor', 'funding', 'organization' → sponsor_name column in aact_multiple_sponsors
  - 'condition', 'disease', 'indication' → conditions column in aact_multiple_sponsors
  - 'country', 'countries' → country column in facilities
  - 'city', 'cities' → city column in facilities
  - 'state', 'states' → state column in facilities
  - 'zip', 'zipcode', 'postal code' → zip column in facilities
  - 'site status', 'facility status' → status column in facilities
  - 'location', 'coordinates' → latitude/longitude columns in facilities
  
  IMPORTANT JOIN PATTERNS:
  - To get sites for specific trials: JOIN facilities f ON aact_multiple_sponsors.nct_id = f.nct_id
  - To get geographic data with trial info: JOIN both tables on nct_id
  - For mapping questions: Always include latitude, longitude, and relevant grouping columns
  
  GEOGRAPHY-RELATED QUERIES:
  - 'map', 'geographic', 'location', 'where' → Include latitude, longitude for mapping
  - 'by country', 'countries' → Group by country column from facilities
  - 'by state', 'states' → Group by state column from facilities
- 'by city', 'cities' → Group by city column from facilities
  "
  
  return(schema_context)
}

# ================================
# SQL GENERATION
# ================================

generate_sql_query <- function(user_question, provider = "groq") {
  schema_info <- get_schema_info()
  
  prompt <- paste0(
    "You are an expert SQL generator for clinical trial data with multiple tables.\n\n",
    "TASK: Convert the user question into a precise SQL query. If user asks for count, consider using distinct count\n\n",
    "USER QUESTION: '", user_question, "'\n\n",
    schema_info, "\n\n",
    "RELATIONSHIP: Both tables connected via 'nct_id' column\n\n",
    
    "SEMANTIC UNDERSTANDING RULES:\n",
    "1. 'clinical trials', 'studies', 'trials' → aact_multiple_sponsors table\n",
    "2. 'sites', 'facilities', 'clinical sites', 'locations' → facilities table\n",
    "3. 'enrollment', 'participants' → enrollment column in aact_multiple_sponsors\n",
    "4. 'phase' → phase column in aact_multiple_sponsors\n",
    "5. 'sponsor' → sponsor_name column in aact_multiple_sponsors\n",
    "6. 'condition', 'disease' → conditions column in aact_multiple_sponsors\n",
    "7. 'country', 'countries' → country column in facilities\n",
    "8. 'city', 'state', 'zip' → respective columns in facilities\n",
    "9. 'site status', 'facility status' → status column in facilities\n",
    "10. 'map', 'geographic', 'coordinates' → include latitude, longitude from facilities\n",
    "11. Use LIKE '%term%' for text searches in SQL\n\n",
    
    "DATA TYPES:\n",
    "1. If question mention dates, assume column names with date as DATE data type\n",
    "2. If question mention datesuse strftime FUNCTION to extract appropriate date\n\n",
    
    "JOIN PATTERNS:\n",
    "- For questions involving both trial data and locations: \n",
    "  JOIN aact_multiple_sponsors a ON facilities f WHERE a.nct_id = f.nct_id\n",
    "- For site counts by trial characteristics:\n",
    "  SELECT relevant_columns FROM aact_multiple_sponsors a JOIN facilities f ON a.nct_id = f.nct_id\n",
    "- For geographic visualization: Always include latitude, longitude when location is mentioned\n\n",
    
    "EXAMPLES:\n",
    "- 'sites for Abbvie NCT123' → SELECT f.country FROM facilities f JOIN aact_multiple_sponsors a ON f.nct_id = a.nct_id WHERE a.sponsor_name LIKE '%Abbvie%' AND a.nct_id = 'NCT123'\n",
    "- 'Novartis sites by phase' → SELECT a.phase, COUNT(DISTINCT f.id) as site_count, f.latitude, f.longitude FROM aact_multiple_sponsors a JOIN facilities f ON a.nct_id = f.nct_id WHERE a.sponsor_name LIKE '%Novartis%' GROUP BY a.phase\n",
    "- 'count of sites by phase' → SELECT a.phase, COUNT(DISTINCT f.id) as site_count FROM aact_multiple_sponsors a JOIN facilities f ON a.nct_id = f.nct_id GROUP BY a.phase\n\n",
    "IMPORTANT: Return ONLY the SQL query. No explanations, no markdown prose, no commentary. ",
    "Wrap the query in a ```sql code block.\n\n",
    "Generate SQL query:"
  )
  
  sql_query <- call_llm_api(prompt, provider = provider)
  
  # Clean SQL query
  # Try to extract just the SQL block from markdown-wrapped responses
  sql_block <- regmatches(sql_query, regexpr("(?s)```(?:sql)?\\s*(.*?)```", sql_query, perl = TRUE))
  if (length(sql_block) > 0) {
    sql_query <- gsub("```(?:sql)?", "", sql_block, perl = TRUE)
  } else {
    # No code fence found — strip any stray backticks and take from first SELECT/WITH
    sql_query <- gsub("```sql|```", "", sql_query)
    first_kw <- regexpr("(?i)\\b(SELECT|WITH|INSERT|UPDATE|DELETE)\\b", sql_query, perl = TRUE)
    if (first_kw > 0) sql_query <- substring(sql_query, first_kw)
  }
  sql_query <- str_trim(sql_query)

  return(sql_query)
}

# ================================
# QUERY EXECUTION
# ================================

execute_sql_query <- function(sql_query) {
  tryCatch({
    result <- dbGetQuery(con, sql_query)
    return(result)
  }, error = function(e) {
    return(data.frame(Error = paste("SQL Error:", e$message)))
  })
}

# ================================
# VISUALIZATION FUNCTIONS
# ================================

create_visualization <- function(data, user_question) {
  if (nrow(data) == 0) return(NULL)
  
  # Check for geographic data - IMPROVED LOGIC
  has_coords <- all(c("latitude", "longitude") %in% names(data))
  has_valid_coords <- FALSE
  
  if (has_coords) {
    # Check if we have valid (non-NA, non-zero) coordinates
    valid_data <- data[!is.na(data$latitude) & !is.na(data$longitude) & 
                         data$latitude != 0 & data$longitude != 0, ]
    has_valid_coords <- nrow(valid_data) > 0
  }
  
  # Determine if user wants geographic visualization
  wants_map <- any(grepl("map|location|geographic|where|sites|facilities", user_question, ignore.case = TRUE))
  
  # PRIORITY 1: Geographic visualization if conditions are met
  if (has_valid_coords && wants_map) {
    message("Creating map visualization with ", nrow(valid_data), " valid coordinates")
    return(list(type = "map", viz = create_map_visualization(data)))
  }
  
  # PRIORITY 2: Regular charts for non-geographic data
  # Determine chart type based on data structure
  numeric_cols <- sapply(data, is.numeric)
  char_cols <- sapply(data, function(x) is.character(x) || is.factor(x))
  
  # Remove coordinate columns from chart consideration
  if (has_coords) {
    numeric_cols[c("latitude", "longitude")] <- FALSE
  }
  
  if (sum(numeric_cols) >= 1 && sum(char_cols) >= 1) {
    # Bar chart for categorical vs numeric
    x_col <- names(data)[char_cols][1]
    y_col <- names(data)[numeric_cols][1]
    
    message("Creating bar chart: ", x_col, " vs ", y_col)
    
    p <- plot_ly(data, x = ~get(x_col), y = ~get(y_col), type = 'bar',
                 marker = list(color = 'rgba(58, 71, 80, 0.6)',
                               line = list(color = 'rgba(58, 71, 80, 1.0)', width = 1))) %>%
      layout(title = paste("Distribution of", y_col, "by", x_col),
             xaxis = list(title = x_col),
             yaxis = list(title = y_col),
             showlegend = FALSE)
    return(list(type = "plot", viz = p))
  }
  
  # If only numeric data, create a simple histogram of the first numeric column
  if (sum(numeric_cols) >= 1) {
    y_col <- names(data)[numeric_cols][1]
    message("Creating histogram for: ", y_col)
    
    p <- plot_ly(data, x = ~get(y_col), type = 'histogram',
                 marker = list(color = 'rgba(58, 71, 80, 0.6)',
                               line = list(color = 'rgba(58, 71, 80, 1.0)', width = 1))) %>%
      layout(title = paste("Distribution of", y_col),
             xaxis = list(title = y_col),
             yaxis = list(title = "Count"),
             showlegend = FALSE)
    return(list(type = "plot", viz = p))
  }
  
  # Default: no visualization, just return table
  message("No suitable visualization found, defaulting to table")
  return(list(type = "table", viz = NULL))
}

create_map_visualization <- function(data) {
  if (!all(c("latitude", "longitude") %in% names(data))) {
    return(NULL)
  }
  
  # Filter out invalid coordinates
  valid_data <- data[!is.na(data$latitude) & !is.na(data$longitude) & 
                       data$latitude != 0 & data$longitude != 0, ]
  
  if (nrow(valid_data) == 0) {
    message("No valid coordinates found for mapping")
    return(NULL)
  }
  
  message("Creating map with ", nrow(valid_data), " valid coordinates")
  
  # Create popup content
  popup_content <- paste(
    "<b>Location:</b>", 
    ifelse("city" %in% names(valid_data), paste(valid_data$city, ","), ""),
    ifelse("state" %in% names(valid_data), paste(valid_data$state, ","), ""),
    ifelse("country" %in% names(valid_data), valid_data$country, ""),
    "<br><b>Coordinates:</b>", round(valid_data$latitude, 4), ",", round(valid_data$longitude, 4),
    if("site_name" %in% names(valid_data)) paste("<br><b>Site:</b>", valid_data$site_name) else "",
    if("nct_id" %in% names(valid_data)) paste("<br><b>NCT ID:</b>", valid_data$nct_id) else ""
  )
  
  # Create leaflet map
  map <- leaflet(valid_data) %>%
    addTiles() %>%
    addMarkers(
      ~longitude, ~latitude,
      popup = popup_content,
      clusterOptions = markerClusterOptions()
    ) %>%
    fitBounds(
      lng1 = min(valid_data$longitude, na.rm = TRUE),
      lat1 = min(valid_data$latitude, na.rm = TRUE),
      lng2 = max(valid_data$longitude, na.rm = TRUE),
      lat2 = max(valid_data$latitude, na.rm = TRUE)
    )
  
  return(map)
}

create_table_view <- function(data) {
  datatable(data, 
            options = list(scrollX = TRUE, pageLength = 10),
            class = 'cell-border stripe')
}

# ================================
# INSIGHT GENERATION
# ================================

generate_insights <- function(data, user_question, sql_query, provider = "groq") {
  if (nrow(data) == 0) {
    return("No data found for your query.")
  }
  
  # Basic statistics
  total_rows <- nrow(data)
  numeric_summary <- ""
  
  numeric_cols <- sapply(data, is.numeric)
  if (any(numeric_cols)) {
    for (col in names(data)[numeric_cols]) {
      if (col %in% c("latitude", "longitude")) next
      col_data <- data[[col]]
      numeric_summary <- paste0(numeric_summary, 
                                "\n- ", col, ": Total = ", sum(col_data, na.rm = TRUE),
                                ", Mean = ", round(mean(col_data, na.rm = TRUE), 2),
                                ", Range = [", min(col_data, na.rm = TRUE), " - ", max(col_data, na.rm = TRUE), "]")
    }
  }
  
  prompt <- paste0(
    "Analyze this clinical trial data.\n\n",
    "USER QUESTION: '", user_question, "'\n",
    "SQL EXECUTED: ", sql_query, "\n\n",
    "DATA SUMMARY:\n",
    "- Total rows: ", total_rows, "\n",
    "- Columns: ", paste(names(data), collapse = ", "), "\n",
    numeric_summary, "\n\n",
    "Provide 2-3 key insights about the data in response to the user's question:"
  )
  
  insights <- call_llm_api(prompt, max_tokens = 300, provider = provider)
  return(insights)
}

# ================================
# MAIN PROCESSING FUNCTION
# ================================

process_user_query <- function(user_question, provider = "groq") {
  tryCatch({
    # Step 1: Generate SQL
    sql_query <- generate_sql_query(user_question, provider = provider)
    
    if (grepl("error", sql_query, ignore.case = TRUE)) {
      return(list(
        response = paste("Error generating SQL:", sql_query),
        data = NULL,
        visualization = NULL,
        sql = sql_query
      ))
    }
    
    # Step 2: Execute SQL
    result_data <- execute_sql_query(sql_query)
    
    if ("Error" %in% names(result_data)) {
      return(list(
        response = result_data$Error[1],
        data = NULL,
        visualization = NULL,
        sql = sql_query
      ))
    }
    
    # Step 3: Generate insights
    #insights <- generate_insights(result_data, user_question, sql_query, provider = provider)
    
    # Step 4: Create visualization
    viz_result <- create_visualization(result_data, user_question)
    
    # Step 5: Compose response
    response_text <- paste0(
      "**Query Executed:**\n```sql\n", sql_query, "\n```\n\n",
      "**Data Retrieved:** ", nrow(result_data), " rows\n\n"
      #,"**Insights:**\n", insights
    )
    
    return(list(
      response = response_text,
      data = result_data,
      visualization = viz_result,
      sql = sql_query
    ))
    
  }, error = function(e) {
    return(list(
      response = paste("Error processing query:", e$message),
      data = NULL,
      visualization = NULL,
      sql = NULL
    ))
  })
}


# ================================
# SHINY UI
# ================================

ui <- dashboardPage(
  dashboardHeader(title = "Clinical Trial LLM Assistant"),
  
  dashboardSidebar(
    sidebarMenu(
      menuItem("Chat", tabName = "chat", icon = icon("comments")),
      menuItem("Data Explorer", tabName = "data", icon = icon("table")),
      menuItem("About", tabName = "about", icon = icon("info"))
    ),
    hr(),
    div(style = "padding: 0 15px;",
      selectInput(
        "llm_provider",
        label   = "LLM Provider",
        choices = c("OpenAI (GPT-4o-mini)" = "openai",
                    "Groq (LLaMA-3.3-70B)"  = "groq"),
        selected = if (GROQ_API_KEY != "") "groq" else "openai"
      )
    )
  ),
  
  dashboardBody(
    useShinyjs(), # Add shinyjs
    tags$head(
      tags$style(HTML("
        .content-wrapper, .right-side {
          background-color: #f4f4f4;
        }
        .chat-container {
          height: 450px; 
          overflow-y: auto; 
          border: 1px solid #ddd; 
          padding: 10px; 
          margin-bottom: 15px;
          background: white;
        }
        .input-group {
          margin-bottom: 0px;
        }
        .form-group {
          margin-bottom: 0px;
        }
      "))
    ),
    
    tabItems(
      # Chat Interface Tab
      tabItem(tabName = "chat",
              # Top Section - Chat Container
              fluidRow(
                box(
                  title = "Clinical Trial Data Assistant", 
                  status = "primary", 
                  solidHeader = TRUE,
                  width = 12,
                  height = "600px",
                  
                  div(
                    class = "chat-container",
                    id = "chat_history",
                    HTML("<div style='color: #666; font-style: italic;'>👋 Hello! I'm your Clinical Trial Data Assistant. Ask me questions about clinical trials, sponsors, locations, and more!</div>")
                  ),
                  
                  div(style = "display: flex; gap: 10px; align-items: flex-end;",
                      div(style = "flex: 1;",
                          textInput("user_input", 
                                    label = NULL,
                                    placeholder = "Ask about clinical trials (e.g., 'Show me top sponsors by enrollment')",
                                    width = "100%")
                      ),
                      div(style = "flex: 0 0 auto;",
                          actionButton("send_btn", "Send", 
                                       class = "btn-primary",
                                       style = "height: 34px;")
                      )
                  )
                )
              ),
              
              # Second Section - Query Info (small height)
              fluidRow(
                box(
                  title = "Query Info", 
                  status = "warning", 
                  solidHeader = TRUE,
                  width = 12,
                  height = "180px",
                  div(style = "height: 100px; overflow-y: auto;",
                      verbatimTextOutput("sql_output")
                  ),
                  br(),
                  downloadButton("download_data", "Download Results", class = "btn-success")
                )
              ),
              
              # Third Section - Visualization and Data Output (equally divided)
              fluidRow(
                box(
                  title = "Visualization", 
                  status = "info", 
                  solidHeader = TRUE,
                  width = 6,
                  height = "500px",
                  div(style = "height: 420px; width: 100%; position: relative;",
                      # Show plot for non-map visualizations
                      conditionalPanel(
                        condition = "output.viz_type == 'plot'",
                        plotlyOutput("plot_output", height = "100%", width = "100%")
                      ),
                      # Show map for geographic visualizations
                      conditionalPanel(
                        condition = "output.viz_type == 'map'",
                        leafletOutput("map_output", height = "100%", width = "100%")
                      ),
                      # Show message when no visualization is available
                      conditionalPanel(
                        condition = "output.viz_type == 'none'",
                        div(style = "height: 100%; display: flex; align-items: center; justify-content: center; color: #666;",
                            "No visualization available for this query")
                      )
                  )
                ),
                
                box(
                  title = "Data Results", 
                  status = "success", 
                  solidHeader = TRUE,
                  width = 6,
                  height = "500px",
                  div(style = "height: 420px;",
                      DT::dataTableOutput("data_output")
                  )
                )
              )
      ),
      
      # Data Explorer Tab
      tabItem(tabName = "data",
              fluidRow(
                box(
                  title = "AACT Multiple Sponsors Table", 
                  status = "primary", 
                  solidHeader = TRUE,
                  width = 12,
                  height = "400px",
                  DT::dataTableOutput("sponsors_table")
                )
              ),
              
              fluidRow(
                box(
                  title = "Facilities Table", 
                  status = "info", 
                  solidHeader = TRUE,
                  width = 12,
                  height = "400px",
                  DT::dataTableOutput("facilities_table")
                )
              )
      ),
      
      # About Tab
      tabItem(tabName = "about",
              fluidRow(
                box(
                  title = "About This Application", 
                  status = "primary", 
                  solidHeader = TRUE,
                  width = 12,
                  HTML("
            <h4>Clinical Trial LLM Assistant</h4>
            <p>This application provides an intelligent interface to explore clinical trial data using natural language queries.</p>
            
            <h5>Features:</h5>
            <ul>
              <li>Natural language to SQL conversion using LLM</li>
              <li>Interactive visualizations and maps</li>
              <li>Geographic analysis of trial sites</li>
              <li>RAG-based context understanding</li>
              <li>Downloadable results</li>
            </ul>
            
            <h5>Technology Stack:</h5>
            <ul>
              <li>R Shiny for UI</li>
              <li>OpenAI GPT-4o-mini <em>or</em> Groq LLaMA-3.3-70B for language processing</li>
              <li>SQLite for data storage</li>
              <li>Plotly & Leaflet for visualizations</li>
              <li>HuggingFace for embeddings</li>
            </ul>
            ")
                )
              )
      )
    )
  )
)

# ================================
# SHINY SERVER
# ================================

server <- function(input, output, session) {
  
  # Reactive values for storing chat history and results
  values <- reactiveValues(
    chat_history = "",
    current_data = NULL,
    current_viz = NULL,
    current_sql = NULL,
    viz_type = "none"  # Track visualization type
  )
  
  # Handle send button click
  observeEvent(input$send_btn, {
    req(input$user_input)
    
    user_question <- input$user_input
    
    # Add user message to chat
    values$chat_history <- paste0(
      values$chat_history,
      "<div style='margin: 10px 0; padding: 10px; background: #e3f2fd; border-radius: 5px;'>",
      "<strong>You:</strong> ", user_question, "</div>"
    )
    
    # Show processing message
    values$chat_history <- paste0(
      values$chat_history,
      "<div id='processing' style='margin: 10px 0; padding: 10px; background: #f5f5f5; border-radius: 5px;'>",
      "<strong>Assistant:</strong> <em>🔄 Processing your query...</em></div>"
    )
    
    # Clear input
    updateTextInput(session, "user_input", value = "")
    
    # Process query synchronously (simpler approach)
    tryCatch({
      result <- process_user_query(user_question, provider = input$llm_provider)
      
      # Remove processing message
      values$chat_history <- gsub(
        "<div id='processing'[^>]*>.*?</div>", 
        "", 
        values$chat_history, 
        perl = TRUE
      )
      
      # Add response
      values$chat_history <- paste0(
        values$chat_history,
        "<div style='margin: 10px 0; padding: 10px; background: #f1f8e9; border-radius: 5px;'>",
        "<strong>Assistant:</strong><br>", 
        gsub("\n", "<br>", gsub("\\*\\*(.*?)\\*\\*", "<strong>\\1</strong>", result$response)), 
        "</div>"
      )
      
      # Store results
      values$current_data <- result$data
      values$current_sql <- result$sql
      
      # Handle visualization result
      if (!is.null(result$visualization)) {
        if (result$visualization$type == "map") {
          values$current_viz <- result$visualization$viz
          values$viz_type <- "map"
        } else if (result$visualization$type == "plot") {
          values$current_viz <- result$visualization$viz
          values$viz_type <- "plot"
        } else {
          values$current_viz <- NULL
          values$viz_type <- "none"
        }
      } else {
        values$current_viz <- NULL
        values$viz_type <- "none"
      }
      
    }, error = function(e) {
      # Remove processing message
      values$chat_history <- gsub(
        "<div id='processing'[^>]*>.*?</div>", 
        "", 
        values$chat_history, 
        perl = TRUE
      )
      
      # Add error message
      values$chat_history <- paste0(
        values$chat_history,
        "<div style='margin: 10px 0; padding: 10px; background: #ffebee; border-radius: 5px; color: #c62828;'>",
        "<strong>Assistant:</strong> ❌ Sorry, I encountered an error: ", e$message, "</div>"
      )
      
      # Reset visualization type on error
      values$viz_type <- "none"
    })
  })
  
  # Handle Enter key in text input
  observe({
    runjs("
      $(document).ready(function() {
        $('#user_input').keypress(function(e) {
          if(e.which == 13) {
            $('#send_btn').click();
          }
        });
        $('#user_input').focus();
      });
    ")
  })
  
  # Update chat display
  observe({
    # Update chat history HTML
    runjs(paste0("$('#chat_history').html('", gsub("'", "\\\\'", values$chat_history), "');"))
    
    # Auto-scroll to bottom
    runjs("$('#chat_history').scrollTop($('#chat_history')[0].scrollHeight);")
  })
  
  # Output the visualization type for conditional panels
  output$viz_type <- reactive({
    values$viz_type
  })
  outputOptions(output, "viz_type", suspendWhenHidden = FALSE)
  
  # Render plot output
  output$plot_output <- renderPlotly({
    if (values$viz_type != "plot" || is.null(values$current_viz)) {
      return(NULL)
    }
    values$current_viz
  })
  
  # Render map output
  output$map_output <- renderLeaflet({
    if (values$viz_type != "map" || is.null(values$current_viz)) {
      return(NULL)
    }
    
    # Ensure the map has proper styling
    values$current_viz %>%
      leaflet::addProviderTiles(providers$OpenStreetMap)  # Ensure tiles are added
  })
  
  # Render data table
  output$data_output <- DT::renderDataTable({
    if (is.null(values$current_data)) {
      return(data.frame(Message = "No data to display"))
    }
    values$current_data
  }, options = list(
    scrollX = TRUE, 
    pageLength = 8, 
    scrollY = "320px",
    dom = 'frtip',  # This ensures pagination is shown properly
    lengthMenu = c(5, 8, 10, 25),
    autoWidth = FALSE
  ))
  
  # Render sponsors table for Data Explorer
  output$sponsors_table <- DT::renderDataTable({
    if (!is.null(clinical_data) && "sponsors" %in% names(clinical_data)) {
      clinical_data$sponsors
    } else {
      data.frame(Message = "Sponsors data not available")
    }
  }, options = list(
    scrollX = TRUE, 
    pageLength = 10, 
    scrollY = "300px",
    dom = 'frtip',
    lengthMenu = c(10, 25, 50, 100),
    autoWidth = FALSE
  ))
  
  # Render facilities table for Data Explorer
  output$facilities_table <- DT::renderDataTable({
    if (!is.null(clinical_data) && "facilities" %in% names(clinical_data)) {
      clinical_data$facilities
    } else {
      data.frame(Message = "Facilities data not available")
    }
  }, options = list(
    scrollX = TRUE, 
    pageLength = 10, 
    scrollY = "300px",
    dom = 'frtip',
    lengthMenu = c(10, 25, 50, 100),
    autoWidth = FALSE
  ))
  
  # Render SQL output
  output$sql_output <- renderText({
    if (is.null(values$current_sql)) {
      return("No SQL query executed yet")
    }
    values$current_sql
  })
  
  # Download handler
  output$download_data <- downloadHandler(
    filename = function() {
      paste("clinical_trial_data_", Sys.Date(), ".csv", sep = "")
    },
    content = function(file) {
      if (!is.null(values$current_data)) {
        write.csv(values$current_data, file, row.names = FALSE)
      }
    }
  )
  
  # Add JavaScript for better UX
  observe({
    runjs("
      // Auto-focus on text input when page loads
      $(document).ready(function() {
        $('#user_input').focus();
        
        // Handle Enter key
        $('#user_input').keypress(function(e) {
          if(e.which == 13 && !e.shiftKey) {
            e.preventDefault();
            $('#send_btn').click();
          }
        });
      });
    ")
  })
}

# ================================
# RUN APPLICATION
# ================================

# Check if running interactively
if (interactive()) {
  message("🚀 Starting Clinical Trial LLM Assistant...")
  message("🔧 Set OPENAI_API_KEY and/or GROQ_API_KEY (plus HUGGINGFACE_API_KEY for embeddings)")
  message("📊 Loading clinical trial data...")
  
  if (!is.null(clinical_data)) {
    message("✅ Data loaded successfully!")
    message("🌐 Starting Shiny application...")
    shinyApp(ui = ui, server = server)
  } else {
    message("❌ Failed to load data. Please check your data files.")
  }
}