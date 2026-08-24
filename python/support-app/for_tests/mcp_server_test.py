import duckdb
from mcp.server.fastmcp import FastMCP

con = duckdb.connect(":memory:")
con.execute("CREATE TABLE t AS SELECT * FROM (VALUES (1,'a'), (2,'b'), (3,'c')) AS v(id, name)")

app = FastMCP("test-log-server", host="127.0.0.1", port=8931)

@app.resource("logs://schema")
def schema() -> str:
    return "views: t(id INTEGER, name VARCHAR)"

@app.tool()
def query_logs(prompt: str = None, sql: str = None) -> str:
    """Run a SQL query, or (if only prompt is given) fake-translate a question to SQL."""
    if not sql:
        if not prompt:
            return "ERROR: provide prompt= or sql="
        sql = "SELECT * FROM t"  # stand-in for real NL->SQL
    try:
        wrapped = f"SELECT * FROM ({sql}) LIMIT 501"
        cur = con.execute(wrapped)
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        truncated = len(rows) > 500
        rows = rows[:500]
        lines = [f"SQL: {sql}", f"rows: {len(rows)}" + (" (truncated at 500)" if truncated else "")]
        lines.append(" | ".join(cols))
        for r in rows:
            lines.append(" | ".join(str(v) for v in r))
        return "\n".join(lines)
    except Exception as e:
        return f"SQL ERROR: {e}"

if __name__ == "__main__":
    app.run(transport="streamable-http")