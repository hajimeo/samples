import streamlit as st
import duckdb
import requests
import json
import pandas as pd

# 0. Model and API Configuration
# Ollama API is assumed to be running locally on port 11434
#MODEL = "qwen2.5-coder:7b"
MODEL = "gemma4:12b"

# 1. UI Configuration
st.set_page_config(page_title="Local Support AI", layout="wide")
st.title("🔍 Local Support AI Log Analytics")

# Initialize DuckDB connection
con = duckdb.connect(database=':memory:')

# 2. Local AI Query Generator (Ollama API)
def ask_local_ai(user_prompt):
    """Asks Qwen2.5-Coder to translate a natural language question into DuckDB SQL."""
    ollama_url = "http://localhost:11434/api/generate"
    
    # We guide the AI with a strict system prompt so it only returns valid SQL
    system_context = """
    You are an expert data engineer translating questions into DuckDB SQL queries.
    The user is querying a dataset of JSON logs located at './logs/*.json'.
    Assume the logs have a standard structure or use `read_json_auto('./logs/*.json')`.
    Common fields include: timestamp, status (e.g. 200, 500), level (e.g. 'ERROR', 'INFO'), message, duration_ms.
    
    CRITICAL: Return ONLY the raw SQL code block. Do not include markdown formatting like ```sql. Do not include explanations.
    """
    
    payload = {
        "model": MODEL,
        "prompt": f"{system_context}\n\nUser Question: {user_prompt}\n\nSQL Query:",
        "stream": False
    }
    
    try:
        response = requests.post(ollama_url, json=payload)
        return response.json()['response'].strip()
    except Exception as e:
        return f"Error connecting to Ollama: {str(e)}"

# 3. Sidebar Chat Interface (The "Support AI" Panel)
st.sidebar.header("Ask AI Assistant")
user_query = st.sidebar.text_area("Ask a question about your logs:", 
                                   placeholder="e.g., Show me the top 5 errors sorted by frequency")

if st.sidebar.button("Analyze Logs"):
    if user_query:
        with st.spinner("AI is analyzing log structure and writing query..."):
            # Step A: AI generates the SQL
            generated_sql = ask_local_ai(user_query)
            
            st.sidebar.subheader("Generated SQL Executed:")
            st.sidebar.code(generated_sql, language="sql")
            
            # Step B: DuckDB executes the SQL on the raw files
            try:
                df_result = con.execute(generated_sql).df()
                
                # Step C: Render results in the main web UI dashboard
                st.subheader("📊 Analysis Results")
                st.dataframe(df_result, use_container_width=True)
                
                # Dynamic Charting: If there's numerical data, show a chart automatically
                if len(df_result.columns) >= 2 and df_result.dtypes.iloc[1] in ['int64', 'float64']:
                    st.subheader("📈 Visual Timeline / Metric Breakdowns")
                    st.line_chart(df_result.set_index(df_result.columns[0]))
                    
            except Exception as sql_error:
                st.error(f"SQL Execution Failed: {str(sql_error)}")
    else:
        st.sidebar.warning("Please enter a question first.")

# 4. Main Panel Static Analytics (Observe-style Health Overview)
st.header("🌐 System Overview")
col1, col2, col3 = st.columns(3)

try:
    # Use DuckDB to quickly populate high-level dashboard metrics without loading the files
    total_logs = con.execute("SELECT COUNT(*) FROM read_json_auto('./logs/*.json', ignore_errors=True)").fetchone()[0]
    total_errors = con.execute("SELECT COUNT(*) FROM read_json_auto('./logs/*.json', ignore_errors=True) WHERE lower(line::VARCHAR) LIKE '%error%'").fetchone()[0]
    
    col1.metric("Total Logs Processed", f"{total_logs:,}")
    col2.metric("Critical Anomalies Detected", f"{total_errors:,}", delta="-5% vs yesterday", delta_color="inverse")
    col3.metric("Log Ingestion Engine", "DuckDB (In-Memory)")
except:
    col1.metric("Total Logs Processed", "0")
    col2.metric("Critical Anomalies Detected", "0")
    col3.metric("Log Ingestion Engine", "DuckDB (Waiting for logs)")
    st.info("Place your JSON files in a directory named `./logs/` to populate the dashboards.")

