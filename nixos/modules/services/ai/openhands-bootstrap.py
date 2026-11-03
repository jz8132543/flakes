import json
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


def bootstrap(config):
    marker = Path(config["marker_file"])
    if marker.exists():
        print("OpenHands already initialized; leaving user settings unchanged")
        return

    key = Path(config["key_file"]).read_text().strip()

    def request(path, method="GET", data=None):
        body = None if data is None else json.dumps(data).encode()
        req = Request(
            config["api_base"] + path,
            data=body,
            method=method,
            headers={"X-Session-API-Key": key, "Content-Type": "application/json"},
        )
        try:
            with urlopen(req, timeout=30) as response:
                return json.load(response) if response.status != 204 else None
        except HTTPError as error:
            # API errors may echo credentials; never print the response body.
            raise RuntimeError(f"OpenHands {method} {path}: HTTP {error.code}") from None

    for attempt in range(60):
        try:
            request("/ready")
            break
        except (RuntimeError, URLError, TimeoutError):
            if attempt == 59:
                raise RuntimeError("OpenHands did not become ready") from None
            time.sleep(2)

    current = request("/api/settings")
    profile_names = {profile["name"] for profile in request("/api/profiles")["profiles"]}
    gateway_key = Path(config["gateway_key_file"]).read_text().strip().splitlines()[0]
    for name, model in config["profiles"].items():
        if name in profile_names:
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
    request("/api/settings", "PATCH", settings)

    workspaces = request("/api/workspaces")["workspaces"]
    if not any(workspace["path"] == "/projects" for workspace in workspaces):
        request(
            "/api/workspaces",
            "POST",
            {"workspaces": [{"id": "projects", "name": "Projects", "path": "/projects"}]},
        )

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
    temporary.write_text(json.dumps({"version": 1, "profiles": list(config["profiles"])}))
    temporary.replace(marker)
    print("OpenHands initialized: tools, memory, MCP, profiles, workspace, and inactive drafts")


if __name__ == "__main__":
    bootstrap(json.loads(Path(sys.argv[1]).read_text()))
