# REQUIREMENTS:
#   # recommend to run in a virtual environment
#   pip install -U streamlit duckdb requests pandas #watchdog
#   jn_utils_v2.py and analyse_logs_v2.py must be in the same directory as this script (or on PYTHONPATH)
#
# HOW TO RUN:
#   1. Start Ollama with AI_MODEL on AI_API_URL
#   2. `cd` to the extracted support zip which has (nexus.log, clm-server.log, request.log, outbound-request.log, audit.log)
#   3. Run this script: streamlit run python/support_app.py --client.toolbarMode="viewer"
import streamlit as st
import requests
import pandas as pd

import jn_utils_v2 as ju
import analyse_logs_v2 as al

# 0. Model and API Configuration
# If the environment variable AI_API_URL is set, use it; otherwise default to localhost
AI_API_URL = st.secrets.get("AI_API_URL", "http://localhost:11434/api/generate")
AI_MODEL = st.secrets.get("AI_MODEL", "qwen2.5-coder:7b") # "gemma4:12b"
LOG_SUFFIX = st.secrets.get("LOG_SUFFIX", ".log")

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

# A short hint per well-known table, to help the AI pick the right one.
KNOWN_TABLE_HINTS = {
    "t_nxrm_logs": "from nexus.log (NXRM3 application log)",
    "t_iq_logs": "from clm-server.log (IQ Server application log)",
    "t_request": "from request.log / outbound-request.log (HTTP access log)",
    "t_audit_logs": "from audit.log / audit.json (audit events, flattened JSON)",
    "t_threads": "from threads.txt (thread dump)",
    "t_log_hazelcast_monitor": "Hazelcast health monitor lines extracted from t_nxrm_logs",
    "t_log_elastic_monitor_jvm": "Elasticsearch JVM monitor lines extracted from t_nxrm_logs",
}


@st.cache_resource(show_spinner="Parsing support zip logs into DuckDB (via jn_utils_v2/analyse_logs_v2) ...")
def load_data():
    """Runs the analyse_logs_v2 ETL pipeline once per app process and returns (connection, error)."""
    con = ju.connect()
    error = None
    try:
        al.etl(log_suffix=LOG_SUFFIX)
    except Exception as e:
        error = str(e)
    return con, error


def build_schema_description():
    """Builds a compact table/column listing of everything currently loaded into DuckDB."""
    tables_df = ju.desc()
    if tables_df is None or tables_df.empty:
        return "(no tables loaded yet)"
    lines = []
    for tablename in tables_df["name"].tolist():
        cols_df = ju.desc(tablename)
        col_names = cols_df["name"].tolist() if cols_df is not None and not cols_df.empty else []
        if len(col_names) > 20:
            col_names = col_names[:20] + ["..."]
        hint = KNOWN_TABLE_HINTS.get(tablename, "")
        suffix = f"  -- {hint}" if hint else ""
        lines.append(f"- {tablename}({', '.join(col_names)}){suffix}")
    return "\n".join(lines)


con, etl_error = load_data()
if etl_error:
    st.warning("ETL could not fully load the logs. The AI assistant may have limited data: " + etl_error)

schema_description = build_schema_description()

# 2. Local AI Query Generator (Ollama API)
def ask_local_ai(user_prompt):
    """Asks Qwen2.5-Coder to translate a natural language question into DuckDB SQL."""
    ollama_url = AI_API_URL

    # We guide the AI with a strict system prompt so it only returns valid SQL
    system_context = f"""
    You are an expert data engineer translating questions into DuckDB SQL queries.
    The following tables are available (table_name(columns...)):
    {schema_description}

    Application log tables (e.g. t_nxrm_logs, t_iq_logs) always have date_time, loglevel, message columns.
    Request log tables (e.g. t_request) always have date, requestURL, statusCode, bytesSent, elapsedTime columns.
    Query the tables above directly, e.g. `SELECT * FROM t_nxrm_logs WHERE loglevel = 'ERROR'`.

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
with st.sidebar.expander("📋 Loaded tables"):
    st.text(schema_description)

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

APP_LOG_TABLES = [t for t in ("t_nxrm_logs", "t_iq_logs") if ju.exists(t)]

try:
    if not APP_LOG_TABLES:
        raise Exception("Neither t_nxrm_logs nor t_iq_logs was loaded.")

    # Use DuckDB to quickly populate high-level dashboard metrics from the structured log tables
    counts_sql = " UNION ALL ".join(f"SELECT loglevel FROM {t}" for t in APP_LOG_TABLES)
    total_logs = con.execute(f"SELECT COUNT(*) FROM ({counts_sql})").fetchone()[0]
    total_errors = con.execute(f"SELECT COUNT(*) FROM ({counts_sql}) WHERE upper(loglevel) LIKE '%ERROR%'").fetchone()[0]

    col1.metric("Total Logs Processed", f"{total_logs:,}")
    col2.metric("Critical Anomalies Detected", f"{total_errors:,}", delta="-5% vs yesterday", delta_color="inverse")
    col3.metric("Log Ingestion Engine", "DuckDB (via jn_utils_v2)")

    st.subheader("📂 Rows per Table")
    rows_per_table = {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] for t in ju.desc()["name"].tolist()}
    category_df = pd.DataFrame(list(rows_per_table.items()), columns=["table", "count"])
    st.bar_chart(category_df.set_index("table"))
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
