# REQUIREMENTS:
#   # recommend to run in a virtual environment
#   pip install -U streamlit duckdb requests pandas #watchdog
#
# HOW TO RUN:
#   1. Start Ollama with AI_MODEL on AI_API_URL
#   2. `cd` to the extracted support zip which has (nexus.log, clm-server.log, request.log, outbound-request.log, audit.log)
#   3. Run this script: streamlit run python/support_app.py --client.toolbarMode="viewer"
import os
import re

import streamlit as st
import duckdb
import requests
import json
import pandas as pd

# 0. Model and API Configuration
# If the environment variable AI_API_URL is set, use it; otherwise default to localhost
AI_API_URL = st.secrets.get("AI_API_URL", "http://localhost:11434/api/generate")
AI_MODEL = st.secrets.get("AI_MODEL", "qwen2.5-coder:7b") # "gemma4:12b"

# 1. UI Configuration/customization
st.set_page_config(page_title="Local SupportZip Analyzer", layout="wide")
st.title("🔍 Local SupportZip Analyzer")
st.text("API URL: {}, Model: {}".format(AI_API_URL, AI_MODEL))

# Hide the Streamlit "Deploy" button in the top-right corner
st.markdown(
    r"""
    <style>
    .stAppDeployButton {
        visibility: hidden;
    }
    </style>
    """,
    unsafe_allow_html=True
)

# Initialize DuckDB connection
con = duckdb.connect(database=':memory:')

# Default Log sources are matching all files under the current directory or `./log/` directory, and file name ends with `.log` or `.log.gz`
# This can be overridden by LOG_APP_REGEX environment variable, which should be a regex pattern matching the log file paths to include.
LOG_APP_REGEX = st.secrets.get("LOG_APP_REGEX", "(nexus|clm-server).*(log|log.gz)$")    # category `application`
LOG_REQ_REGEX = st.secrets.get("LOG_REQ_REGEX", "request.*(log|log.gz)$")               # category `request`
LOG_OUTBOUND_REGEX = st.secrets.get("LOG_OUTBOUND_REGEX", "outbound-request.*(log|log.gz)$")    # category `outbound`
LOG_AUDIT_REGEX = st.secrets.get("LOG_AUDIT_REGEX", "audit.*(log|log.gz)$")             # category `audit`

LOG_CATEGORY_REGEXES = {
    "application": LOG_APP_REGEX,
    "request": LOG_REQ_REGEX,
    "outbound": LOG_OUTBOUND_REGEX,
    "audit": LOG_AUDIT_REGEX,
}

def find_log_files():
    """Walks the current directory and groups matching file paths by category."""
    compiled = {category: re.compile(pattern) for category, pattern in LOG_CATEGORY_REGEXES.items()}
    matches = {category: [] for category in LOG_CATEGORY_REGEXES}
    for root, _, files in os.walk("."):
        for fname in files:
            path = os.path.join(root, fname)
            for category, pattern in compiled.items():
                if pattern.search(path):
                    matches[category].append(path)
    return matches

def setup_log_views(con):
    """Creates a unified `logs` view over the categorized log files, one row per line."""
    union_parts = []
    for category, paths in find_log_files().items():
        if not paths:
            continue
        # it seems read_text has 4GB limit, so changed to read_csv but not tested yet.
        union_parts.append(f"""
            SELECT
                line,
                '{category}' AS category,
                filename AS source_file
            FROM read_csv(
                {paths},
                columns={{'line': 'VARCHAR'}},
                sep='\\x01',
                quote='',
                escape='',
                header=false,
                filename=true,
                strict_mode=false
            )
            WHERE line != ''
        """)
    if not union_parts:
        raise Exception("No log files found matching the configured LOG_*_REGEX patterns.")
    # Currently creating one large table contains all log lines....
    con.execute(f"CREATE OR REPLACE VIEW logs AS {' UNION ALL '.join(union_parts)}")

try:
    setup_log_views(con)
except Exception as e:
    # report error but continue; the user may not have logs yet
    st.warning("Some log files are missing or could not be read. The AI assistant may have limited data: " + str(e))
    pass

# 2. Local AI Query Generator (Ollama API)
def ask_local_ai(user_prompt):
    """Asks Qwen2.5-Coder to translate a natural language question into DuckDB SQL."""
    ollama_url = AI_API_URL

    # We guide the AI with a strict system prompt so it only returns valid SQL
    system_context = """
    You are an expert data engineer translating questions into DuckDB SQL queries.
    The user is querying a DuckDB view named `logs`, built from plain-text log files.
    Columns: line (the raw log line text), category ('application', 'request', or 'audit'), source_file (originating file path).
    'application' comes from nexus.log, 'request' comes from request.log/outbound-request.log, 'audit' comes from audit.log.
    Query the `logs` view directly, e.g. `SELECT * FROM logs WHERE category = 'application'`.

    CRITICAL: Return ONLY the raw SQL code block. Do not include markdown formatting like ```sql. Do not include explanations.
    """
    
    payload = {
        "model": AI_MODEL,
        "prompt": f"{system_context}\n\nUser Question: {user_prompt}\n\nSQL Query:",
        "stream": False
    }
    
    try:
        response = requests.post(ollama_url, json=payload)
        return response.json()['response'].strip()
    except Exception as e:
        return f"Error connecting to Ollama: {str(e)}"

def run_sql(sql):
    """Executes SQL against DuckDB and renders the results/chart in the main panel."""
    try:
        df_result = con.execute(sql).df()

        st.subheader("📊 Analysis Results")
        st.dataframe(df_result, use_container_width=True)

        # Dynamic Charting: If there's numerical data, show a chart automatically
        if len(df_result.columns) >= 2 and df_result.dtypes.iloc[1] in ['int64', 'float64']:
            st.subheader("📈 Visual Timeline / Metric Breakdowns")
            st.line_chart(df_result.set_index(df_result.columns[0]))

    except Exception as sql_error:
        st.error(f"SQL Execution Failed: {str(sql_error)}")

# 3. Sidebar Chat Interface (The "Support AI" Panel)
st.sidebar.header("Ask AI Assistant")
user_query = st.sidebar.text_area("Ask a question about your logs:",
                                   placeholder="e.g., Show me the top 5 errors sorted by frequency")

if "sql_editor" not in st.session_state:
    st.session_state.sql_editor = ""

run_now = False
if st.sidebar.button("Analyze Logs"):
    if user_query:
        with st.spinner("AI is analyzing log structure and writing query..."):
            generated_sql = ask_local_ai(user_query)
            # Even though instructed to remove ```sql ... ```, some AI still returns it, so we clean it up
            if generated_sql.startswith("```sql"):
                generated_sql = generated_sql.replace("```sql", "").replace("```", "").strip()
            st.session_state.sql_editor = generated_sql
            run_now = True
    else:
        st.sidebar.warning("Please enter a question first.")

st.sidebar.subheader("SQL Query (editable)")
st.sidebar.text_area("Edit or write raw SQL, then run it:", key="sql_editor", height=150)

if run_now or st.sidebar.button("Run SQL"):
    if st.session_state.sql_editor.strip():
        run_sql(st.session_state.sql_editor)
    else:
        st.sidebar.warning("Enter or generate a SQL query first.")

# 4. Main Panel Static Analytics (Observe-style Health Overview)
st.header("🌐 System Overview")
col1, col2, col3 = st.columns(3)

try:
    # Use DuckDB to quickly populate high-level dashboard metrics from the categorized logs
    total_logs = con.execute("SELECT COUNT(*) FROM logs").fetchone()[0]
    total_errors = con.execute("SELECT COUNT(*) FROM logs WHERE lower(line) LIKE '%error%'").fetchone()[0]

    col1.metric("Total Logs Processed", f"{total_logs:,}")
    col2.metric("Critical Anomalies Detected", f"{total_errors:,}", delta="-5% vs yesterday", delta_color="inverse")
    col3.metric("Log Ingestion Engine", "DuckDB (In-Memory)")

    st.subheader("📂 Logs by Category")
    category_df = con.execute("SELECT category, COUNT(*) AS count FROM logs GROUP BY category ORDER BY category").df()
    st.bar_chart(category_df.set_index("category"))
except Exception as e:
    col1.metric("Total Logs Processed", "0")
    col2.metric("Critical Anomalies Detected", "0")
    col3.metric("Log Ingestion Engine", "DuckDB (Waiting for logs)")
    st.info(
        "Place your log files at `./log/nexus.log` (application), "
        "`./log/request.log` and `./log/outbound-request.log` (request/outbound), "
        "and `./log/audit.log` (audit) to populate the dashboards."
    )
    st.error(f"Error reading logs or creating views: {str(e)}")
    st.exception(e)
