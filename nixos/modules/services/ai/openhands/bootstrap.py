import json
import os
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


def bootstrap(config):
    marker = Path(config["marker_file"])
    key = Path(config["key_file"]).read_text().strip()

    def request(path, method="GET", data=None, *, expect_json=True):
        body = None if data is None else json.dumps(data).encode()
        req = Request(
            config["api_base"] + path,
            data=body,
            method=method,
            headers={"X-Session-API-Key": key, "Content-Type": "application/json"},
        )
        try:
            with urlopen(req, timeout=30) as response:
                if expect_json and response.status != 204:
                    return json.load(response)
        except HTTPError as error:
            # API errors may echo credentials; never print the response body.
            raise RuntimeError(f"OpenHands {method} {path}: HTTP {error.code}") from None

    for attempt in range(60):
        try:
            request("/ready", expect_json=False)
            break
        except (RuntimeError, URLError, TimeoutError):
            if attempt == 59:
                raise RuntimeError("OpenHands did not become ready") from None
            time.sleep(2)

    current = request("/api/settings")
    gateway_key = Path(config["gateway_key_file"]).read_text().strip().splitlines()[0]
    current_profiles = {profile["name"]: profile for profile in request("/api/profiles")["profiles"]}
    for name, model in config["profiles"].items():
        current_profile = current_profiles.get(name)
        if (
            current_profile
            and current_profile.get("model") == f"openai/{model}"
            and current_profile.get("base_url") == config["gateway_base"]
        ):
            continue
        request(
            f"/api/profiles/{quote(name)}",
            "POST",
            {
                "llm": {
                    "model": f"openai/{model}",
                    "base_url": config["gateway_base"],
                    "api_key": gateway_key,
                    "api_mode": "chat",
                    "stream": True,
                    "max_output_tokens": 8192,
                    "reasoning_effort": "high" if name == "reasoning" else "medium",
                },
                "include_secrets": True,
            },
        )

    settings = config["settings"]
    if not current.get("llm_api_key_is_set"):
        settings["active_profile"] = "default"

    agent_settings = settings.setdefault("agent_settings_diff", {})
    mcp_config = dict((current.get("agent_settings_diff") or {}).get("mcp_config") or {})
    old_managed = set()
    if marker.exists():
        try:
            old_managed = set(json.loads(marker.read_text()).get("mcp_servers", []))
        except (OSError, ValueError):
            old_managed = set()
    declared_mcp = json.loads(json.dumps(config.get("mcp_servers", {})))
    for name in old_managed - set(declared_mcp):
        mcp_config.pop(name, None)
    for name, path in config.get("mcp_secret_files", {}).items():
        if name not in declared_mcp:
            raise RuntimeError(f"MCP secret configured for undeclared server: {name}")
        token = Path(path).read_text().strip()
        headers = declared_mcp[name].setdefault("headers", {})
        headers["Authorization"] = f"Bearer {token}"
    mcp_config.update(declared_mcp)
    agent_settings["mcp_config"] = mcp_config
    request("/api/settings", "PATCH", settings)

    workspaces = request("/api/workspaces")["workspaces"]
    configured_paths = {workspace.get("path") for workspace in workspaces}
    missing_workspaces = [
        {"id": name, "name": name.title(), "path": f"/{name}"}
        for name in config.get("workspaces", [])
        if f"/{name}" not in configured_paths
    ]
    if missing_workspaces:
        request(
            "/api/workspaces",
            "POST",
            {"workspaces": missing_workspaces},
        )

    if config["drafts"]:
        capabilities = request("/api/automation/v1/capabilities")
        if "automationDrafts" not in capabilities.get("features", []):
            raise RuntimeError("Automation backend does not support safe drafts")
        drafts = request("/api/automation/v1/drafts")
        if isinstance(drafts, dict):
            drafts = drafts.get("items", drafts.get("drafts", []))
        draft_names = {draft.get("name") for draft in drafts}
        for draft in config["drafts"]:
            if draft["name"] in draft_names:
                continue
            request(
                "/api/automation/v1/drafts",
                "POST",
                {
                    "endpoint": "/v1/preset/prompt",
                    "name": draft["name"],
                    "draft": {
                        "name": draft["name"],
                        "prompt": draft["prompt"],
                        "model": "default",
                        "enabled": False,
                        "trigger": {
                            "type": "cron",
                            "schedule": draft["schedule"],
                            "timezone": "Asia/Shanghai",
                        },
                    },
                },
            )

    temporary = marker.with_suffix(".tmp")
    temporary.write_text(json.dumps({
        "version": 2,
        "profiles": list(config["profiles"]),
        "mcp_servers": list(declared_mcp),
    }))
    temporary.chmod(0o600)
    temporary.replace(marker)
    print("OpenHands declarative profiles, MCP servers, workspaces, and drafts reconciled")


if __name__ == "__main__":
    config = json.loads(Path(sys.argv[1]).read_text())
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    config["marker_file"] = str(Path(os.environ["STATE_DIRECTORY"]) / "managed.json")
    for field in ("key_file", "gateway_key_file"):
        config[field] = credentials / config[field]
    config["mcp_secret_files"] = {
        name: credentials / file for name, file in config["mcp_secret_files"].items()
    }
    bootstrap(config)
