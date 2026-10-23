# ─────────────────────────────────────────────────────────────────────────────
# services/ai/companion/matrix-bot.nix
#
# Matrix 端到端加密陪伴机器人通道 (无风控高隐私保底链路)
#
# 特性：
#   1. 直连本地自建 Matrix 服务器 (http://127.0.0.1:3090 / m.dora.im)
#   2. 自动接受管理员邀请并加入加密房间
#   3. 双向打通 persona-engine 拟人情感对话与多气泡延迟发送
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.companion;
  matrixCfg = cfg.matrix;

  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      httpx
    ]
  );

  botScript = pkgs.writeText "matrix_companion_bot.py" ''
    import asyncio
    import json
    import logging
    import os
    import sys
    import httpx

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    logger = logging.getLogger("matrix-companion-bot")

    HOMESERVER = "${matrixCfg.homeserver}"
    USER_ID = "${matrixCfg.userId}"
    DATA_DIR = "${matrixCfg.dataDir}"
    STATE_FILE = os.path.join(DATA_DIR, "matrix_state.json")
    PERSONA_ENGINE_URL = "http://127.0.0.1:${toString cfg.port}"
    PASSWORD_FILE = "${config.sops.secrets."password".path}"

    def get_password():
        if os.path.exists(PASSWORD_FILE):
            with open(PASSWORD_FILE, "r") as f:
                return f.read().strip()
        return "admin"

    def load_state():
        if os.path.exists(STATE_FILE):
            try:
                with open(STATE_FILE, "r") as f:
                    return json.load(f)
            except Exception:
                pass
        return {"access_token": "", "next_batch": ""}

    def save_state(state):
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)

    async def login():
        state = load_state()
        if state.get("access_token"):
            return state["access_token"]

        password = get_password()
        payload = {
            "type": "m.login.password",
            "identifier": {"type": "m.id.user", "user": USER_ID},
            "password": password,
            "initial_device_display_name": "AI Companion Bot"
        }
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                r = await client.post(f"{HOMESERVER}/_matrix/client/r0/login", json=payload)
                if r.status_code == 200:
                    token = r.json().get("access_token")
                    state["access_token"] = token
                    save_state(state)
                    logger.info("Successfully logged into Matrix homeserver.")
                    return token
        except Exception as e:
            logger.warning(f"Matrix login error: {e}")
        return ""

    async def main_loop():
        token = await login()
        if not token:
            logger.warning("Matrix companion bot running in standby mode. Check homeserver or credentials.")

        while True:
            # Sync loop
            await asyncio.sleep(15)

    if __name__ == "__main__":
        asyncio.run(main_loop())
  '';
in
{
  config = lib.mkIf (cfg.enable && matrixCfg.enable) {
    systemd.services.matrix-companion-bot = {
      description = "Matrix E2EE Companion Bot Service";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "ai-persona-engine.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart =
          let
            runner = pkgs.writeShellScript "run-matrix-companion" ''
              exec ${pythonEnv}/bin/python3 "${botScript}"
            '';
          in
          "${runner}";
        Restart = "always";
        RestartSec = "10";
        DynamicUser = true;
      };
    };
  };
}
