# REQUIREMENTS:
#   pip install -U "mcp[cli]<2"
#
# A thin CLI wrapper around support_app.py's MCP server (see work/demo-mcp/support-logs-app/SKILL.md), so
# an agent can run one command instead of re-writing the async MCP client boilerplate every time.
#
# USAGE:
#   python query_logs_client.py --schema
#   python query_logs_client.py --sql "SELECT loglevel, COUNT(*) FROM application_logs GROUP BY loglevel"
#   python query_logs_client.py --prompt "how many errors are there"
#   python query_logs_client.py --url http://127.0.0.1:8931/mcp --sql "..."   # non-default host/port
import argparse
import asyncio
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


async def _run(url, sql, prompt):
    try:
        async with streamablehttp_client(url) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                if sql is None and prompt is None:
                    res = await session.read_resource("logs://schema")
                    print(res.contents[0].text)
                    return True
                args = {}
                if sql is not None:
                    args["sql"] = sql
                if prompt is not None:
                    args["prompt"] = prompt
                result = await session.call_tool("query_logs", args)
                print(result.content[0].text)
                return True
    except Exception as e:
        print(f"ERROR: could not reach MCP server at {url} - is it running? "
              f"(start it with: python support_app.py --mcp)\n{e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="Query support_app.py's MCP log server from the CLI.")
    parser.add_argument("--url", default="http://127.0.0.1:8931/mcp",
                         help="MCP server URL (default: http://127.0.0.1:8931/mcp)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--sql", help="Run this DuckDB SQL directly against the log views.")
    group.add_argument("--prompt", help="Natural-language question, translated to SQL via the local model.")
    group.add_argument("--schema", action="store_true", help="Print the logs://schema resource (view/column reference).")
    args = parser.parse_args()

    sql = args.sql
    prompt = None if args.schema or args.sql else args.prompt
    asyncio.run(_run(args.url, sql, prompt))


if __name__ == "__main__":
    main()
