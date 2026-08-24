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
            print("SCHEMA (first 200 chars):", res.contents[0].text[:200])
            print()

            r1 = await session.call_tool("query_logs", {"sql": "SELECT loglevel, COUNT(*) c FROM application_logs GROUP BY loglevel"})
            print("=== sql= result ===")
            print(r1.content[0].text)
            print()

            r2 = await session.call_tool("query_logs", {"sql": "SELECT domain, type FROM audit_logs WHERE parsed"})
            print("=== audit sql= result ===")
            print(r2.content[0].text)
            print()

            r3 = await session.call_tool("query_logs", {"sql": "SELECT * FROM totally_bogus_table"})
            print("=== error result ===")
            print(r3.content[0].text)
            print()

            r4 = await session.call_tool("query_logs", {})
            print("=== no-args result ===")
            print(r4.content[0].text)

asyncio.run(main())
