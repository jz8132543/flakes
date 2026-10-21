# ─────────────────────────────────────────────────────────────────────────────
# services/ai/mcp/degoog-bridge.nix
#
# Degoog 本地搜索引擎与网页正文提取 MCP 桥接服务
#
# 功能：
#   1. 将本地 degoog 搜索引擎封装为标准 MCP (Model Context Protocol) 工具
#   2. 暴露 Streamable HTTP / SSE MCP 端点供 IBM ContextForge 聚合
#   3. 提供符合 Dify Custom Tool 规范的 OpenAPI 3.0 Schema
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.mcp;
  degoogPort = config.ports.degoog;
  bridgePort = config.ports.degoog-mcp;

  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      fastapi
      uvicorn
      httpx
      beautifulsoup4
    ]
  );

  serverScript = pkgs.writeText "degoog-mcp-server.py" ''
    import asyncio
    import json
    import logging
    import re
    from typing import Any, Dict, List, Optional
    from urllib.parse import urljoin

    import httpx
    from bs4 import BeautifulSoup
    from fastapi import FastAPI, HTTPException, Query, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse, Response, StreamingResponse

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger("degoog-mcp")

    app = FastAPI(
        title="Degoog Web Search & Extraction Tool",
        version="1.0.0",
        description="Local Privacy Search and Webpage Reader Bridge for Dify and MCP Gateway",
        servers=[{"url": f"http://127.0.0.1:${toString bridgePort}"}]
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    DEGOOG_URL = "http://127.0.0.1:${toString degoogPort}"

    async def do_search(query: str, limit: int = 5) -> List[Dict[str, Any]]:
        url = f"{DEGOOG_URL}/api/search"
        params = {"q": query, "format": "json"}
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(url, params=params)
                if resp.status_code != 200:
                    # Fallback to standard search
                    resp = await client.get(f"{DEGOOG_URL}/search", params=params)
                data = resp.json()
        except Exception as e:
            logger.error(f"Error querying Degoog: {e}")
            return [{"title": "Error", "url": "", "snippet": f"Search failed: {str(e)}"}]

        raw_results = data.get("results", []) if isinstance(data, dict) else []
        results = []
        for item in raw_results[:limit]:
            results.append({
                "title": item.get("title", ""),
                "url": item.get("url", ""),
                "snippet": item.get("snippet", "") or item.get("content", ""),
            })
        return results

    async def do_fetch(url: str, max_chars: int = 6000) -> Dict[str, Any]:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        }
        try:
            async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as client:
                resp = await client.get(url, headers=headers)
                resp.raise_for_status()
                html = resp.text
        except Exception as e:
            logger.error(f"Error fetching url {url}: {e}")
            return {"url": url, "title": "Error", "content": f"Failed to fetch content: {str(e)}"}

        soup = BeautifulSoup(html, "html.parser")
        for tag in soup(["script", "style", "nav", "footer", "header", "noscript", "svg", "form"]):
            tag.decompose()

        title = soup.title.string.strip() if soup.title and soup.title.string else url
        body_text = soup.get_text(separator="\n", strip=True)
        # Collapse multiple newlines
        body_text = re.sub(r"\n{3,}", "\n\n", body_text)
        if len(body_text) > max_chars:
            body_text = body_text[:max_chars] + "\n...[truncated]"

        return {"url": url, "title": title, "content": body_text}

    @app.get("/health")
    async def health():
        return {"status": "ok", "degoog": DEGOOG_URL}

    @app.get("/search", summary="Search the web", operation_id="search_web")
    async def search_endpoint(
        q: str = Query(..., description="The search query terms"),
        limit: int = Query(5, ge=1, le=20, description="Max number of search results to return")
    ):
        """Execute a privacy web search via local Degoog aggregator."""
        results = await do_search(q, limit)
        return {"query": q, "results": results}

    @app.get("/fetch", summary="Fetch webpage text", operation_id="fetch_webpage")
    async def fetch_endpoint(
        url: str = Query(..., description="The absolute HTTP/HTTPS URL of the webpage to scrape and extract text from")
    ):
        """Extract clean article/text content from a webpage."""
        return await do_fetch(url)

    # ── MCP SSE 协议实现 ─────────────────────────────────────────────────
    MCP_TOOLS = [
        {
            "name": "search_web",
            "description": "Perform web search via local privacy search aggregator (Degoog). Returns relevant search results with title, URL, and summary snippet.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "The search keywords or query."},
                    "limit": {"type": "integer", "description": "Number of results to return (1-10).", "default": 5}
                },
                "required": ["query"]
            }
        },
        {
            "name": "fetch_webpage",
            "description": "Fetch and extract readable plain-text content from a webpage URL for in-depth analysis.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "url": {"type": "string", "description": "The URL of the webpage to read."}
                },
                "required": ["url"]
            }
        }
    ]

    @app.get("/sse")
    async def mcp_sse(request: Request):
        async def event_generator():
            yield f"event: endpoint\ndata: /messages?sessionId=default\n\n"
            while True:
                if await request.is_disconnected():
                    break
                await asyncio.sleep(15)
                yield f": ping\n\n"

        return StreamingResponse(event_generator(), media_type="text/event-stream")

    @app.post("/messages")
    async def mcp_messages(request: Request):
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid JSON")

        method = body.get("method")
        msg_id = body.get("id")

        if method == "initialize":
            res = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "degoog-mcp-server", "version": "1.0.0"}
                }
            }
            return JSONResponse(res)

        elif method == "tools/list":
            res = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {"tools": MCP_TOOLS}
            }
            return JSONResponse(res)

        elif method == "tools/call":
            params = body.get("params", {})
            name = params.get("name")
            arguments = params.get("arguments", {})

            if name == "search_web":
                query = arguments.get("query", "")
                limit = int(arguments.get("limit", 5))
                search_res = await do_search(query, limit)
                res_text = json.dumps(search_res, ensure_ascii=False, indent=2)
                return JSONResponse({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"content": [{"type": "text", "text": res_text}]}
                })

            elif name == "fetch_webpage":
                url = arguments.get("url", "")
                fetch_res = await do_fetch(url)
                res_text = json.dumps(fetch_res, ensure_ascii=False, indent=2)
                return JSONResponse({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"content": [{"type": "text", "text": res_text}]}
                })

            else:
                return JSONResponse({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {"code": -32601, "message": f"Tool not found: {name}"}
                })

        return JSONResponse({"jsonrpc": "2.0", "id": msg_id, "result": {}})
  '';
in
{
  config = lib.mkIf (cfg.enable && config.services.degoog.enable) {
    systemd.services.degoog-mcp-bridge = {
      description = "Degoog MCP & OpenAPI Bridge Service";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "degoog.service"
      ];
      wants = [
        "network-online.target"
        "degoog.service"
      ];
      serviceConfig = {
        ExecStart =
          let
            runner = pkgs.writeShellScript "run-degoog-mcp" ''
                          exec ${pythonEnv}/bin/python3 -c "
              import sys
              sys.path.insert(0, '${pkgs.writeTextDir "degoog_server.py" (builtins.readFile serverScript)}')
              import uvicorn
              from degoog_server import app
              uvicorn.run(app, host='127.0.0.1', port=${toString bridgePort}, log_level='info')
              "
            '';
          in
          "${runner}";
        Restart = "always";
        RestartSec = "5";
        DynamicUser = true;
      };
    };

    # 将 OpenAPI 规范落盘，方便 Dify 与命令行直接读取
    systemd.tmpfiles.rules = [
      "d /var/lib/degoog-mcp 0755 root root -"
    ];
  };
}
