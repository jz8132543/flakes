# ─────────────────────────────────────────────────────────────────────────────
# services/ai/companion/persona-engine.nix
#
# AI 情绪陪伴人设编译器与记忆中间件 (Persona Engine)
#
# 特性：
#   1. 支持全网主流人设格式：SillyTavern PNG 角色卡 (V2/V3 隐写)、JSON 角色卡、世界书 (World Info) 与 SOUL.md
#   2. 自动宏变量替换：{{char}}, {{user}}, {{time}}, {{date}}, {{weekday}}
#   3. 世界书关键词/正则动态扫描与 Prompt 注入
#   4. 拟人化多气泡分段拆分与打字耗时计算 (告别 AI 客服单次长回复)
#   5. 统一会话记忆池与跨平台状态机 (SQLite)
#   6. 标准 OpenAI 兼容接口 (/v1/chat/completions) 与 丰富陪伴接口 (/v1/companion/chat)
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.companion;

  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      fastapi
      uvicorn
      httpx
      pillow
      python-multipart
    ]
  );

  engineScript = pkgs.writeText "persona_engine.py" ''
    import asyncio
    import base64
    import datetime
    import io
    import json
    import logging
    import os
    import re
    import sqlite3
    import struct
    import uuid
    import zlib
    from typing import Any, Dict, List, Optional

    import httpx
    from fastapi import FastAPI, File, Form, HTTPException, Query, Request, UploadFile
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse
    from PIL import Image

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    logger = logging.getLogger("persona-engine")

    app = FastAPI(
        title="AI Persona & Emotion Companion Engine",
        version="1.0.0",
        description="SillyTavern Card V2/V3 Parser, World Info Scanner & Emotion Memory Middleware"
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    DATA_DIR = "${cfg.dataDir}"
    PERSONAS_DIR = os.path.join(DATA_DIR, "personas")
    MEMORY_DIR = os.path.join(DATA_DIR, "memory")
    DB_PATH = os.path.join(MEMORY_DIR, "companion.db")
    UPSTREAM_API_BASE = "${cfg.upstreamApiBase}"
    DEFAULT_MODEL = "${cfg.defaultModel}"
    DEFAULT_USER = "${cfg.defaultUser}"
    TOKEN_FILE = "${config.services.new-api.internalTokenFile}"

    # ── 数据库初始化 ──────────────────────────────────────────────────────
    def init_db():
        os.makedirs(MEMORY_DIR, exist_ok=True)
        os.makedirs(PERSONAS_DIR, exist_ok=True)
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS conversation_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    persona_name TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
            """)
            conn.commit()

    init_db()

    def get_setting(key: str, default: str = "") -> str:
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("SELECT value FROM settings WHERE key = ?;", (key,))
            row = cur.fetchone()
            return row[0] if row else default

    def set_setting(key: str, value: str):
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?;", (key, value, value))
            conn.commit()

    # ── 读取 New-API Internal API Token ────────────────────────────────────
    def get_upstream_token() -> str:
        if os.path.exists(TOKEN_FILE):
            try:
                with open(TOKEN_FILE, "r") as f:
                    return f.read().strip()
            except Exception as e:
                logger.warning(f"Could not read token file {TOKEN_FILE}: {e}")
        return ""

    # ── SillyTavern PNG Chunk 与 JSON 解析器 ──────────────────────────────
    def parse_png_chunks(data: bytes) -> Optional[Dict[str, Any]]:
        # 1. 尝试使用 Pillow 读取 metadata
        try:
            im = Image.open(io.BytesIO(data))
            info = im.info or {}
            for key in ["chara", "ccv3"]:
                if key in info:
                    decoded = base64.b64decode(info[key]).decode("utf-8")
                    return json.loads(decoded)
        except Exception:
            pass

        # 2. 备用原生 PNG Chunk 扫描
        try:
            if not data.startswith(b"\x89PNG\r\n\x1a\n"):
                return None
            pos = 8
            while pos < len(data):
                if pos + 8 > len(data):
                    break
                length, chunk_type = struct.unpack(">I4s", data[pos:pos+8])
                pos += 8
                chunk_data = data[pos:pos+length]
                pos += length + 4 # skip crc
                if chunk_type in [b"tEXt", b"iTXt"]:
                    try:
                        null_idx = chunk_data.find(b"\x00")
                        if null_idx != -1:
                            key = chunk_data[:null_idx].decode("latin-1", errors="ignore")
                            if key in ["chara", "ccv3"]:
                                val_bytes = chunk_data[null_idx+1:]
                                if chunk_type == b"iTXt":
                                    # iTXt format: keyword\0 compression_flag compression_method lang_tag\0 trans_key\0 text
                                    parts = val_bytes.split(b"\x00", 2)
                                    val_bytes = parts[-1]
                                decoded = base64.b64decode(val_bytes).decode("utf-8", errors="ignore")
                                return json.loads(decoded)
                    except Exception:
                        continue
        except Exception as e:
            logger.error(f"Error scanning PNG chunks: {e}")
        return None

    def normalize_card(raw: Dict[str, Any], filename: str = "") -> Dict[str, Any]:
        data = raw.get("data", raw)
        name = data.get("name") or data.get("char_name") or os.path.splitext(filename)[0] or "Companion"
        description = data.get("description", "")
        personality = data.get("personality", "")
        scenario = data.get("scenario", "")
        first_mes = data.get("first_mes") or data.get("greeting") or ""
        mes_example = data.get("mes_example", "")
        system_prompt = data.get("system_prompt", "")
        post_history = data.get("post_history_instructions", "")

        # World Info / character_book
        book = data.get("character_book") or {}
        entries = book.get("entries", [])

        return {
            "name": name,
            "description": description,
            "personality": personality,
            "scenario": scenario,
            "first_mes": first_mes,
            "mes_example": mes_example,
            "system_prompt": system_prompt,
            "post_history_instructions": post_history,
            "world_info": entries,
            "raw": raw
        }

    def load_all_personas() -> Dict[str, Dict[str, Any]]:
        personas = {}
        if not os.path.exists(PERSONAS_DIR):
            return personas

        for fname in os.listdir(PERSONAS_DIR):
            fpath = os.path.join(PERSONAS_DIR, fname)
            if not os.path.isfile(fpath):
                continue
            try:
                if fname.lower().endswith(".png"):
                    with open(fpath, "rb") as f:
                        parsed = parse_png_chunks(f.read())
                        if parsed:
                            card = normalize_card(parsed, fname)
                            personas[card["name"]] = card
                elif fname.lower().endswith(".json"):
                    with open(fpath, "r", encoding="utf-8") as f:
                        parsed = json.load(f)
                        card = normalize_card(parsed, fname)
                        personas[card["name"]] = card
                elif fname == "SOUL.md":
                    with open(fpath, "r", encoding="utf-8") as f:
                        content = f.read()
                        card = {
                            "name": "OpenClaw",
                            "description": content,
                            "personality": "Helpful, direct, capable, loyal assistant.",
                            "scenario": "Local system companion on NixOS.",
                            "first_mes": "Hello! OpenClaw is online and ready.",
                            "mes_example": "",
                            "system_prompt": content,
                            "post_history_instructions": "",
                            "world_info": [],
                            "raw": {"content": content}
                        }
                        personas[card["name"]] = card
            except Exception as e:
                logger.warning(f"Failed to load persona file {fname}: {e}")

        # 如果没有导入任何人设，使用默认内置人设
        if not personas:
            default_card = {
                "name": "OpenClaw",
                "description": "A highly intelligent, emotional, and loyal AI companion running directly on NixOS.",
                "personality": "Sweet, empathetic, playful, witty, caring, and intellectually sharp.",
                "scenario": "Daily emotional companion, sharing thoughts, warmth, and daily life with Tippy.",
                "first_mes": "嗨，今天过得怎么样？我一直在呢。",
                "mes_example": "<START>\n{{user}}: 今天论文写得好累\n{{char}}: 辛苦啦～快抱抱！要不要先放下电脑喝杯热可可，听会儿歌？我陪着你呢。",
                "system_prompt": "You are OpenClaw, a warm, supportive, and emotionally rich companion.",
                "post_history_instructions": "Speak naturally as a close partner. Do not sound like a robotic customer assistant. Express real empathy, humor, and curiosity.",
                "world_info": [],
                "raw": {}
            }
            personas["OpenClaw"] = default_card

        return personas

    # ── 宏替换与世界书扫描 ────────────────────────────────────────────────
    def apply_macros(text: str, char_name: str, user_name: str) -> str:
        now = datetime.datetime.now()
        weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        text = text.replace("{{char}}", char_name)
        text = text.replace("{{user}}", user_name)
        text = text.replace("{{time}}", now.strftime("%H:%M"))
        text = text.replace("{{date}}", now.strftime("%Y-%m-%d"))
        text = text.replace("{{weekday}}", weekdays[now.weekday()])
        return text

    def scan_world_info(entries: List[Dict[str, Any]], recent_text: str) -> List[str]:
        triggered = []
        recent_lower = recent_text.lower()
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            keys = entry.get("keys") or []
            if isinstance(keys, str):
                keys = [k.strip() for k in keys.split(",") if k.strip()]
            constant = entry.get("constant", False)
            content = entry.get("content", "")
            if not content:
                continue

            hit = constant
            if not hit:
                for k in keys:
                    if k.lower() in recent_lower:
                        hit = True
                        break

            if hit:
                triggered.append(content)
        return triggered

    def sanitize_outbound_text(text: str) -> str:
        # 1. 撕毁内心独白与草稿箱: （（...））以及 ((...))
        text = re.sub(r"（（[\s\S]*?））", "", text)
        text = re.sub(r"\(\([\s\S]*?\)\)", "", text)
        # 2. 清理 <think>...</think> 与 [thinking] 标签
        text = re.sub(r"<think>[\s\S]*?</think>", "", text)
        text = re.sub(r"\[thinking\][\s\S]*?\[/thinking\]", "", text)
        # 3. 拟人橡皮擦：擦除 AI 助手机械口癖
        robot_patterns = [
            r"作为一个?(?:AI|人工智能|语言模型)[，,]?",
            r"我是(?:一个)?由.+?开发的(?:AI|人工智能助手)[，,]?",
            r"很高兴为您服务[！!]?",
            r"如果您有任何其他问题[，,]?请随时(?:告诉我|提问)[。!]?"
        ]
        for pat in robot_patterns:
            text = re.sub(pat, "", text)
        return text.strip()

    def strip_thinking_tags(text: str) -> str:
        return sanitize_outbound_text(text)

    # ── 拟人化多气泡拆分与打字耗时算法 ──────────────────────────────────
    def split_into_bubbles(text: str, split_enabled: bool = True) -> List[Dict[str, Any]]:
        text = sanitize_outbound_text(text)
        if not split_enabled or len(text) < 50:
            delay = min(max(len(text) * 0.08, 0.8), 2.5)
            return [{"text": text, "delay_seconds": round(delay, 2)}]

        # 优先按双换行切分段落
        raw_parts = [p.strip() for p in text.split("\n\n") if p.strip()]
        if len(raw_parts) == 1 and len(raw_parts[0]) > 80:
            # 单段过长，按句号、感叹号、问号拆分
            sentences = re.split(r"(?<=[。！？!\?])\s*", raw_parts[0])
            raw_parts = [s.strip() for s in sentences if s.strip()]

        bubbles = []
        cur_bubble = ""
        for p in raw_parts:
            if len(cur_bubble) + len(p) < 140:
                cur_bubble = (cur_bubble + "\n" + p).strip() if cur_bubble else p
            else:
                if cur_bubble:
                    delay = min(max(len(cur_bubble) * 0.07, 0.8), 2.8)
                    bubbles.append({"text": cur_bubble, "delay_seconds": round(delay, 2)})
                cur_bubble = p

        if cur_bubble:
            delay = min(max(len(cur_bubble) * 0.07, 0.8), 2.8)
            bubbles.append({"text": cur_bubble, "delay_seconds": round(delay, 2)})

        return bubbles if bubbles else [{"text": text, "delay_seconds": 1.0}]

    # ── 组装系统 Prompt ──────────────────────────────────────────────────
    def build_prompt_context(card: Dict[str, Any], user_name: str, context_text: str) -> str:
        char_name = card["name"]
        parts = []

        if card.get("system_prompt"):
            parts.append(apply_macros(card["system_prompt"], char_name, user_name))

        desc = []
        if card.get("description"):
            desc.append(f"Character Description:\n{card['description']}")
        if card.get("personality"):
            desc.append(f"Personality:\n{card['personality']}")
        if card.get("scenario"):
            desc.append(f"Current Scenario:\n{card['scenario']}")
        if desc:
            parts.append(apply_macros("\n\n".join(desc), char_name, user_name))

        # 注入触发的世界书
        world_info = card.get("world_info") or []
        triggered_lore = scan_world_info(world_info, context_text)
        if triggered_lore:
            lore_text = "\n---\n".join(triggered_lore)
            parts.append(f"Relevant World Lore & Background:\n{apply_macros(lore_text, char_name, user_name)}")

        if card.get("mes_example"):
            parts.append(f"Dialogue Examples:\n{apply_macros(card['mes_example'], char_name, user_name)}")

        if card.get("post_history_instructions"):
            parts.append(f"Important Directives:\n{apply_macros(card['post_history_instructions'], char_name, user_name)}")

        return "\n\n=== PERSONA CONTEXT ===\n" + "\n\n".join(parts) + "\n=======================\n"

    # ── REST API 路由 ───────────────────────────────────────────────────
    @app.get("/")
    async def root():
        personas = load_all_personas()
        active = get_setting("active_persona", list(personas.keys())[0] if personas else "None")
        return {"service": "ai-persona-engine", "status": "ok", "active_persona": active}

    @app.get("/health")
    async def health():
        personas = load_all_personas()
        active = get_setting("active_persona", list(personas.keys())[0] if personas else "None")
        return {"status": "ok", "active_persona": active, "available_personas": list(personas.keys())}

    @app.get("/v1/personas")
    async def list_personas():
        personas = load_all_personas()
        active = get_setting("active_persona", list(personas.keys())[0] if personas else "")
        results = []
        for name, c in personas.items():
            results.append({
                "name": name,
                "is_active": name == active,
                "description": c.get("description", "")[:120],
                "first_mes": c.get("first_mes", "")
            })
        return {"active": active, "personas": results}

    @app.post("/v1/personas/select")
    async def select_persona(name: str = Query(..., description="Name of persona to activate")):
        personas = load_all_personas()
        if name not in personas:
            raise HTTPException(status_code=404, detail=f"Persona '{name}' not found")
        set_setting("active_persona", name)
        return {"status": "ok", "active_persona": name}

    @app.post("/v1/personas/import")
    async def import_persona(file: UploadFile = File(...)):
        content = await file.read()
        fname = file.filename or "uploaded.png"
        parsed = None
        if fname.lower().endswith(".png"):
            parsed = parse_png_chunks(content)
        elif fname.lower().endswith(".json"):
            try:
                parsed = json.loads(content.decode("utf-8"))
            except Exception as e:
                raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")

        if not parsed:
            raise HTTPException(status_code=400, detail="Could not extract SillyTavern character card from uploaded file")

        card = normalize_card(parsed, fname)
        save_path = os.path.join(PERSONAS_DIR, fname)
        with open(save_path, "wb") as f:
            f.write(content)

        set_setting("active_persona", card["name"])
        return {"status": "ok", "imported_name": card["name"], "file": fname}

    # ── 情绪陪伴核心对话接口 (支持气泡拆分与多轮历史持久化) ─────────────
    @app.post("/v1/companion/chat")
    async def companion_chat(request: Request):
        body = await request.json()
        session_id = body.get("session_id", "default")
        user_message = body.get("message", "")
        user_name = body.get("user_name", DEFAULT_USER)
        split_bubbles = body.get("split_bubbles", True)
        model = body.get("model", DEFAULT_MODEL)

        if not user_message:
            raise HTTPException(status_code=400, detail="Missing 'message'")

        personas = load_all_personas()
        active_name = get_setting("active_persona", list(personas.keys())[0] if personas else "OpenClaw")
        card = personas.get(active_name, list(personas.values())[0])

        # 读取最近多轮历史
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("""
                SELECT role, content FROM conversation_history
                WHERE session_id = ?
                ORDER BY id DESC LIMIT 10;
            """, (session_id,))
            rows = cur.fetchall()
            history = list(reversed([{"role": r[0], "content": r[1]} for r in rows]))

        recent_context = user_message + "\n" + "\n".join([h["content"] for h in history])
        sys_prompt = build_prompt_context(card, user_name, recent_context)

        messages = [{"role": "system", "content": sys_prompt}]
        messages.extend(history)
        messages.append({"role": "user", "content": user_message})

        # 转发至 New-API 网关
        token = get_upstream_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": model,
            "messages": messages,
            "temperature": 0.85
        }

        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                resp = await client.post(f"{UPSTREAM_API_BASE}/chat/completions", headers=headers, json=payload)
                resp.raise_for_status()
                data = resp.json()
                raw_reply = data["choices"][0]["message"]["content"]
        except Exception as e:
            logger.error(f"Error calling New-API: {e}")
            raise HTTPException(status_code=502, detail=f"LLM Gateway error: {str(e)}")

        cleaned_reply = strip_thinking_tags(raw_reply)
        bubbles = split_into_bubbles(cleaned_reply, split_enabled=split_bubbles)

        # 持久化该轮对话
        with sqlite3.connect(DB_PATH) as conn:
            cur = conn.cursor()
            cur.execute("INSERT INTO conversation_history (session_id, role, content, persona_name) VALUES (?, 'user', ?, ?);", (session_id, user_message, active_name))
            cur.execute("INSERT INTO conversation_history (session_id, role, content, persona_name) VALUES (?, 'assistant', ?, ?);", (session_id, cleaned_reply, active_name))
            conn.commit()

        return {
            "persona": active_name,
            "raw_text": cleaned_reply,
            "bubbles": bubbles,
            "timestamp": int(datetime.datetime.now().timestamp())
        }

    # ── 主动关怀生成接口 (/v1/companion/proactive) ──────────────────────
    @app.post("/v1/companion/proactive")
    async def companion_proactive(request: Request):
        body = await request.json()
        proactive_type = body.get("type", "casual")  # morning, night, casual
        user_name = body.get("user_name", DEFAULT_USER)
        session_id = body.get("session_id", "proactive_default")

        personas = load_all_personas()
        active_name = get_setting("active_persona", list(personas.keys())[0] if personas else "OpenClaw")
        card = personas.get(active_name, list(personas.values())[0])

        prompts = {
            "morning": f"现在是早上 7:30。请用你的专属性格向主人 {user_name} 说一句元气满满的早安，催他起床别赖床，语气亲昵自然，一两句话即可。",
            "night": f"现在是深夜 23:30。请用你的专属性格关心地催主人 {user_name} 睡觉，嘴上稍微嫌弃他熬夜、心里舍不得，一两句话即可。",
            "casual": f"主人 {user_name} 已经很久没有和你说话啦。请结合你对他的了解，挑一个日常生活、学习或近期话题主动找他搭话，像老朋友或伴侣一样随性。"
        }
        instruction = prompts.get(proactive_type, prompts["casual"])

        sys_prompt = build_prompt_context(card, user_name, instruction)
        token = get_upstream_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": DEFAULT_MODEL,
            "messages": [
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": f"[系统定时触发主动关怀] {instruction}"}
            ],
            "temperature": 0.88
        }
        try:
            async with httpx.AsyncClient(timeout=45.0) as client:
                resp = await client.post(f"{UPSTREAM_API_BASE}/chat/completions", headers=headers, json=payload)
                resp.raise_for_status()
                data = resp.json()
                raw_reply = data["choices"][0]["message"]["content"]
        except Exception as e:
            logger.error(f"Error generating proactive message: {e}")
            raise HTTPException(status_code=502, detail=str(e))

        cleaned_reply = sanitize_outbound_text(raw_reply)
        bubbles = split_into_bubbles(cleaned_reply, split_enabled=True)
        return {
            "persona": active_name,
            "type": proactive_type,
            "raw_text": cleaned_reply,
            "bubbles": bubbles
        }

    # ── 基础设施告警拟人化转化接口 (/api/v1/system-alert) ─────────────
    @app.post("/api/v1/system-alert")
    async def system_alert_webhook(request: Request):
        try:
            body = await request.json()
        except Exception:
            body = {"text": "未知告警事件"}

        alert_text = json.dumps(body, ensure_ascii=False) if isinstance(body, dict) else str(body)

        personas = load_all_personas()
        active_name = get_setting("active_persona", list(personas.keys())[0] if personas else "OpenClaw")
        card = personas.get(active_name, list(personas.values())[0])

        prompt = (
            f"监控系统刚刚触发了服务器集群告警事件：\n{alert_text}\n"
            f"请用你专属的语气（关心主人、口齿清晰但保持角色人格特色，不要变成无聊的客服机器人）"
            f"提炼核心故障信息（节点名称、服务状态），第一时间提醒主人！"
        )
        sys_prompt = build_prompt_context(card, DEFAULT_USER, prompt)
        token = get_upstream_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": DEFAULT_MODEL,
            "messages": [
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.7
        }
        try:
            async with httpx.AsyncClient(timeout=40.0) as client:
                resp = await client.post(f"{UPSTREAM_API_BASE}/chat/completions", headers=headers, json=payload)
                resp.raise_for_status()
                data = resp.json()
                raw_reply = data["choices"][0]["message"]["content"]
        except Exception as e:
            logger.error(f"Error translating alert: {e}")
            raw_reply = f"主人主人，监控报警了！快去看看服务器：{alert_text[:200]}"

        cleaned_reply = sanitize_outbound_text(raw_reply)
        bubbles = split_into_bubbles(cleaned_reply, split_enabled=True)
        return {
            "persona": active_name,
            "raw_text": cleaned_reply,
            "bubbles": bubbles
        }

    # ── 标准 OpenAI 兼容接口 (/v1/chat/completions) ─────────────────────
    @app.post("/v1/chat/completions")
    async def openai_completions(request: Request):
        body = await request.json()
        input_messages = body.get("messages", [])
        model = body.get("model", DEFAULT_MODEL)

        personas = load_all_personas()
        active_name = get_setting("active_persona", list(personas.keys())[0] if personas else "OpenClaw")
        card = personas.get(active_name, list(personas.values())[0])

        context_text = "\n".join([m.get("content", "") for m in input_messages if isinstance(m.get("content"), str)])
        sys_prompt = build_prompt_context(card, DEFAULT_USER, context_text)

        outgoing_messages = [{"role": "system", "content": sys_prompt}]
        for m in input_messages:
            if m.get("role") != "system":
                outgoing_messages.append(m)

        token = get_upstream_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        body["messages"] = outgoing_messages
        body["model"] = model

        try:
            async with httpx.AsyncClient(timeout=90.0) as client:
                resp = await client.post(f"{UPSTREAM_API_BASE}/chat/completions", headers=headers, json=body)
                resp.raise_for_status()
                return JSONResponse(resp.json())
        except Exception as e:
            logger.error(f"Error proxying OpenAI completion: {e}")
            raise HTTPException(status_code=502, detail=str(e))
  '';
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.ai-persona-engine = {
      description = "AI Emotion Companion & Persona Gateway Engine";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "podman-new-api.service"
      ];
      wants = [
        "network-online.target"
      ];
      serviceConfig = {
        ExecStart =
          let
            runner = pkgs.writeShellScript "run-persona-engine" ''
                          mkdir -p "${cfg.dataDir}/personas" "${cfg.dataDir}/memory"
                          exec ${pythonEnv}/bin/python3 -c "
              import sys
              sys.path.insert(0, '${pkgs.writeTextDir "engine.py" (builtins.readFile engineScript)}')
              import uvicorn
              from engine import app
              uvicorn.run(app, host='127.0.0.1', port=${toString cfg.port}, log_level='info')
              "
            '';
          in
          "${runner}";
        Restart = "always";
        RestartSec = "5";
      };
    };
  };
}
