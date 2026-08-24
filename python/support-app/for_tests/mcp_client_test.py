import asyncio
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

async def main():
    async with streamablehttp_client("http://127.0.0.1:8931/mcp") as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            print("TOOLS:", [t.name for t in tools.tools])

            resources = await session.list_resources()
            print("RESOURCES:", [str(r.uri) for r in resources.resources])

            res = await session.read_resource("logs://schema")
            print("SCHEMA:", res.contents[0].text)

            result = await session.call_tool("query_logs", {"sql": "SELECT * FROM t WHERE id > 1"})
            print("SQL RESULT:\n", result.content[0].text)

            result2 = await session.call_tool("query_logs", {"prompt": "show me everything"})
            print("PROMPT RESULT:\n", result2.content[0].text)

            result3 = await session.call_tool("query_logs", {"sql": "SELECT * FROM nonexistent_table"})
            print("ERROR RESULT:\n", result3.content[0].text)

asyncio.run(main())