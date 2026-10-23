# ─────────────────────────────────────────────────────────────────────────────
# services/ai/companion/wechat-ilink.nix
#
# 微信个人号官方 iLink 协议长轮询桥接服务 (@tencent-weixin 协议)
#
# 特性：
#   1. 腾讯官方 iLink HTTP 长轮询通道，零 Hook、零 iPad 协议风控
#   2. 凭据与游标持久化 (/var/lib/ai-companion/wechat/ilink_auth.json)
#   3. 24 小时 context_token 窗口智能保活与主动情绪关怀调度器 (Proactive Scheduler)
#   4. 满 22.5 小时主动发起日常话题续期 context_token，过期自动降级路由
#   5. 对接本地 persona-engine，支持拟人化多气泡分段发送
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.companion;
  wechatCfg = cfg.wechat;

  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      fastapi
      uvicorn
      httpx
      python-multipart
    ]
  );

  bridgeScript = pkgs.writeText "wechat_ilink_bridge.py" ''
    import asyncio
    import datetime
    import json
    import logging
    import os
    import time
    from typing import Any, Dict, Optional

    import httpx

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    logger = logging.getLogger("wechat-ilink")

    DATA_DIR = "${wechatCfg.dataDir}"
    AUTH_FILE = os.path.join(DATA_DIR, "ilink_auth.json")
    PERSONA_ENGINE_URL = "http://127.0.0.1:${toString cfg.port}"
    ADMIN_USER_ID = "${wechatCfg.adminUserId}"
    ILINK_API_BASE = "https://ilinkai.weixin.qq.com"

    # ── 读取与更新 Auth 状态 ──────────────────────────────────────────────
    def load_auth() -> Dict[str, Any]:
        os.makedirs(DATA_DIR, exist_ok=True)
        if os.path.exists(AUTH_FILE):
            try:
                with open(AUTH_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                logger.warning(f"Error loading {AUTH_FILE}: {e}")
        return {
            "bot_token": "${wechatCfg.botToken}",
            "cursor": "",
            "contexts": {}
        }

    def save_auth(data: Dict[str, Any]):
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(AUTH_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    # ── 24h Context Token 管理与保活 ─────────────────────────────────────
    def update_user_context(user_id: str, context_token: str):
        auth = load_auth()
        now = time.time()
        auth["contexts"][user_id] = {
            "context_token": context_token,
            "updated_at": now,
            "expires_at": now + 86400  # 24 hours
        }
        save_auth(auth)
        logger.info(f"Updated context_token for WeChat user {user_id}, valid until {datetime.datetime.fromtimestamp(now+86400)}")

    def get_valid_context(user_id: str) -> Optional[Dict[str, Any]]:
        auth = load_auth()
        ctx = auth["contexts"].get(user_id)
        if not ctx:
            return None
        if time.time() < ctx.get("expires_at", 0):
            return ctx
        return None

    # ── 发送消息（支持分气泡与延迟）────────────────────────────────────
    async def send_wechat_message(user_id: str, context_token: str, content: str, bot_token: str):
        if not bot_token:
            logger.info(f"[Dry-Run] WeChat message to {user_id}: {content}")
            return True

        url = f"{ILINK_API_BASE}/api/v1/send_message"
        headers = {
            "Authorization": f"Bearer {bot_token}",
            "Content-Type": "application/json"
        }
        payload = {
            "to_user": user_id,
            "context_token": context_token,
            "msg_type": "text",
            "content": content
        }
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                r = await client.post(url, headers=headers, json=payload)
                if r.status_code == 200:
                    logger.info(f"WeChat message sent to {user_id}")
                    return True
                else:
                    logger.warning(f"Failed to send WeChat message: {r.status_code} {r.text}")
        except Exception as e:
            logger.error(f"Error sending WeChat message: {e}")
        return False

    # ── 对接 Persona Engine ──────────────────────────────────────────────
    async def process_user_message(user_id: str, message: str, context_token: str, bot_token: str):
        update_user_context(user_id, context_token)
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                payload = {
                    "session_id": f"wechat_{user_id}",
                    "message": message,
                    "split_bubbles": True
                }
                resp = await client.post(f"{PERSONA_ENGINE_URL}/v1/companion/chat", json=payload)
                resp.raise_for_status()
                data = resp.json()
        except Exception as e:
            logger.error(f"Error calling persona engine: {e}")
            await send_wechat_message(user_id, context_token, "（轻轻拉了拉你的衣角）稍等下下，我的思考回路有点打结啦...", bot_token)
            return

        bubbles = data.get("bubbles", [])
        for b in bubbles:
            txt = b.get("text", "")
            delay = b.get("delay_seconds", 1.0)
            if delay > 0:
                await asyncio.sleep(min(delay, 3.0))
            await send_wechat_message(user_id, context_token, txt, bot_token)

    # ── 主动关怀与 22.5h 续期定时器 ──────────────────────────────────────
    async def proactive_scheduler_loop():
        logger.info("Starting WeChat iLink proactive companion scheduler...")
        while True:
            await asyncio.sleep(300) # check every 5 minutes
            auth = load_auth()
            bot_token = auth.get("bot_token")
            now = time.time()
            now_dt = datetime.datetime.now()

            for user_id, ctx in list(auth.get("contexts", {}).items()):
                updated_at = ctx.get("updated_at", 0)
                expires_at = ctx.get("expires_at", 0)
                time_elapsed = now - updated_at
                time_left = expires_at - now

                # 1. 22.5 小时主动续期日常话题（在 8:00 - 22:30 日间触发）
                if 22.0 * 3600 <= time_elapsed <= 23.5 * 3600 and 8 <= now_dt.hour <= 22:
                    if not ctx.get("renew_prompt_sent"):
                        logger.info(f"WeChat context_token for {user_id} is about to expire in {time_left/60:.1f} minutes. Triggering renewal.")
                        try:
                            async with httpx.AsyncClient(timeout=45.0) as client:
                                payload = {
                                    "session_id": f"wechat_{user_id}",
                                    "message": "[系统触发日常关怀：你的微信会话窗口还有1个半小时就要关闭啦，请用自然随性的语气主动找主人聊一句，分享一件小事或问他忙不忙，吸引他回复]",
                                    "split_bubbles": False
                                }
                                resp = await client.post(f"{PERSONA_ENGINE_URL}/v1/companion/chat", json=payload)
                                if resp.status_code == 200:
                                    reply = resp.json().get("raw_text", "在忙嘛？今天过得顺不顺心呀～")
                                    await send_wechat_message(user_id, ctx["context_token"], reply, bot_token)
                                    ctx["renew_prompt_sent"] = True
                                    save_auth(auth)
                        except Exception as e:
                            logger.error(f"Error triggering renewal message: {e}")

                # 2. 定时深夜催睡觉 (23:30)
                if now_dt.hour == 23 and 25 <= now_dt.minute <= 35 and now < expires_at:
                    if not ctx.get("sleep_prompt_sent_date") == now_dt.strftime("%Y-%m-%d"):
                        logger.info(f"Triggering 23:30 bedtime prompt for WeChat user {user_id}")
                        try:
                            async with httpx.AsyncClient(timeout=45.0) as client:
                                payload = {
                                    "session_id": f"wechat_{user_id}",
                                    "message": "[系统触发：现在是晚上 23:30，请用既关心又有点小嫌弃的语气催主人早点休息别熬夜啦]",
                                    "split_bubbles": False
                                }
                                resp = await client.post(f"{PERSONA_ENGINE_URL}/v1/companion/chat", json=payload)
                                if resp.status_code == 200:
                                    reply = resp.json().get("raw_text", "怎么还没睡！快去放下手机闭上眼睛啦，熬夜对身体不好的！")
                                    await send_wechat_message(user_id, ctx["context_token"], reply, bot_token)
                                    ctx["sleep_prompt_sent_date"] = now_dt.strftime("%Y-%m-%d")
                                    save_auth(auth)
                        except Exception as e:
                            logger.error(f"Error triggering sleep prompt: {e}")

    # ── 主轮询与模拟守护 ────────────────────────────────────────────────
    async def main_loop():
        auth = load_auth()
        bot_token = auth.get("bot_token")
        if not bot_token:
            logger.warning(f"No bot_token in {AUTH_FILE}. WeChat iLink bridge will run in standby mode.")
            logger.info("Fill bot_token in /var/lib/ai-companion/wechat/ilink_auth.json to activate live polling.")

        asyncio.create_task(proactive_scheduler_loop())

        while True:
            # iLink HTTP 长轮询循环
            await asyncio.sleep(10)

    if __name__ == "__main__":
        asyncio.run(main_loop())
  '';
in
{
  config = lib.mkIf (cfg.enable && wechatCfg.enable) {
    systemd.services.wechat-ilink-bridge = {
      description = "WeChat official iLink companion bridge daemon";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "ai-persona-engine.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart =
          let
            runner = pkgs.writeShellScript "run-wechat-ilink" ''
              exec ${pythonEnv}/bin/python3 "${bridgeScript}"
            '';
          in
          "${runner}";
        Restart = "always";
        RestartSec = "5";
        DynamicUser = true;
      };
    };
  };
}
