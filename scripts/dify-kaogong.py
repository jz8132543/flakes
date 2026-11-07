"""Auditable Dify teacher configuration; only apply changes remote configuration."""

import argparse
import base64
import copy
import fcntl
import hashlib
import http.cookies
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "conf/dify-kaogong"
APP_NAME = "考公老师方法对照"
MODEL_PROVIDER = "langgenius/openai_api_compatible/openai_api_compatible"
MODEL_NAME = "API"
PLUGIN_ID = "langgenius/openai_api_compatible:0.0.73@4cf123ffaa4556f079bed6c47f3a462cc825504b859b183239e74eb19136a4b5"
VERSION = "1.19.0"
DSL_VERSION = "0.7.0"
REVISION = "8e689e868b63b6dd2b449d0eb568ca5cc7127759"
DIGESTS = {
    "dify-api": "sha256:0d67842aedcb9b5884f75b88c4a5dd812e637916bff1ca892831f7ace2f3204f",
    "dify-web": "sha256:f5f1ad000d6a268ae6b29b84c5095069fbd5994cbe43f937a3d32caa00038b4c",
}
MAX_RESPONSE = 8 * 1024 * 1024


class Blocked(Exception):
    """A safe-to-print error; never include server response bodies or credentials."""


class ApiError(Blocked):
    def __init__(self, method, status=None):
        self.status = status
        super().__init__(
            f"{method}: HTTP {status}"
            if status
            else f"{method}: transport failure; reconcile before retrying writes"
        )


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def load_module(name):
    spec = importlib.util.spec_from_file_location(
        "kaogong_" + name, ASSETS / (name + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_assets():
    data = {
        name: json.loads((ASSETS / (name + ".json")).read_text())
        for name in ("sources", "methods", "taxonomy")
    }
    nodes = load_module("nodes")
    nodes.validate_catalog(data["taxonomy"], data["sources"], data["methods"])
    return data


def summary(data):
    methods = [m for m in data["methods"]["methods"] if m["status"] == "approved"]
    return {
        "candidate_count": len(data["sources"]["candidates"]),
        "approved_method_count": len(methods),
        "approved_teacher_count": len({m["teacher_id"] for m in methods}),
        "verified_teacher_count": 0,
        "delivery_mode": "native-teacher-workflow" if methods else "empty-catalog-only",
        "requires_live_acceptance": True,
        "limitations": [
            "Model configuration is not proof of working upstream authorization.",
            "Only successful real teacher previews establish end-to-end acceptance.",
            "Vision is disabled; community attribution is not teacher endorsement.",
        ],
    }


def default_binding(data):
    return {
        "dataset_id": "00000000-0000-0000-0000-000000000000",
        "retrieval_top_k": len(
            [m for m in data["methods"]["methods"] if m["status"] == "approved"]
        ),
        "provider": MODEL_PROVIDER,
        "model": MODEL_NAME,
        "dependencies": [
            {
                "type": "marketplace",
                "value": {"marketplace_plugin_unique_identifier": PLUGIN_ID},
            }
        ],
    }


def knowledge_module():
    spec = importlib.util.spec_from_file_location(
        "kaogong_knowledge", ROOT / "scripts/dify_kaogong_knowledge.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bundle(data, binding=None):
    methods = [m for m in data["methods"]["methods"] if m["status"] == "approved"]
    workflow = load_module("workflow")
    code = (ASSETS / "nodes.py").read_text()
    if methods:
        binding = dict(binding or default_binding(data))
        code += "\n" + (ASSETS / "teacher_nodes.py").read_text()
        code += (
            "\n# Third-party data notices:\n"
            + "\n".join(
                "# " + line
                for line in (ASSETS / "THIRD_PARTY_LICENSES.txt")
                .read_text()
                .splitlines()
            )
            + "\n"
        )
        dsl = workflow.build_teacher_workflow(code, data, binding)
        workflow.validate_teacher_workflow(dsl)
    else:
        dsl = workflow.build_workflow(code)
        workflow.validate_workflow(dsl)
    names = {
        candidate["teacher_id"]: candidate["name"]
        for candidate in data["sources"]["candidates"]
    }
    manifest = {
        "schema_version": 1,
        "dify_version": VERSION,
        "dsl_version": DSL_VERSION,
        "source_revision": REVISION,
        "images": DIGESTS,
        "summary": summary(data),
        "catalog_sha256": digest(data),
        "dsl_sha256": digest(dsl),
        "documents": [
            {
                "skill_id": m["skill_id"],
                "teacher_id": m["teacher_id"],
                "topic_id": m["topic_id"],
                "content_hash": m["content_hash"],
            }
            for m in methods
        ],
        "teacher_directory": [
            {
                "teacher_id": teacher,
                "name": names[teacher],
                "skill_ids": sorted(
                    m["skill_id"] for m in methods if m["teacher_id"] == teacher
                ),
            }
            for teacher in sorted({m["teacher_id"] for m in methods})
        ],
        "retrieval": "native-hard-filtered" if methods else "disabled-empty-catalog",
        "binding": binding,
        "requires_binding": bool(
            methods and binding["dataset_id"] == "00000000-0000-0000-0000-000000000000"
        ),
        "publish": False,
        "enable_site": False,
        "enable_api": False,
    }
    return dsl, manifest


def private_dir(path):
    path = Path(path)
    if path.is_symlink():
        raise Blocked("Runtime directory must not be a symlink")
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.stat()
    if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise Blocked("Runtime directory must be owned by the caller with mode 0700")
    return path


def save_text(path, content):
    path = Path(path)
    private_dir(path.parent)
    fd, temporary = tempfile.mkstemp(prefix=".kaogong-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def save_json(path, data):
    save_text(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def write_bundle(path, dsl, manifest, data):
    private_dir(path)
    save_json(path / "chatflow.yml", dsl)
    save_json(path / "manifest.json", manifest)
    save_json(path / "catalog.json", data)
    if manifest["binding"]:
        save_json(path / "binding.json", manifest["binding"])
    save_text(
        path / "THIRD_PARTY_LICENSES.txt",
        (ASSETS / "THIRD_PARTY_LICENSES.txt").read_text(),
    )


def read_private(path):
    # sops runtime paths may be symlinks; validate the opened target, not its link.
    with open(path, "rb") as stream:
        info = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid not in {0, os.geteuid()}
            or stat.S_IMODE(info.st_mode) & 0o077
        ):
            raise Blocked(
                "Credential/state file must be private and owned by root or the caller"
            )
        content = stream.read(MAX_RESPONSE + 1)
    if len(content) > MAX_RESPONSE:
        raise Blocked("Credential/state file exceeds size limit")
    return content.decode()


def repair_model_limits(client, provider, model, state_dir):
    """Normalize limits using Dify's keep-secret sentinel, never its display mask."""
    if provider != MODEL_PROVIDER:
        raise Blocked(
            "Numeric repair requires the reviewed OpenAI-compatible credential schema"
        )
    path = "/workspaces/current/model-providers/" + provider + "/models/credentials"
    result = client.api(
        "GET",
        path + "?" + urllib.parse.urlencode({"model": model, "model_type": "llm"}),
    )
    credentials = result.get("credentials", {})
    changes = {}
    for field in ("context_size", "max_tokens_to_sample"):
        value = credentials.get(field)
        if isinstance(value, str) and re.fullmatch(
            r"[1-9][0-9]{0,2}(?:,[0-9]{3})+", value
        ):
            changes[field] = {"before": value, "after": value.replace(",", "")}
    if not changes:
        return {"changed": False, "model": model}
    credential_id = str(uuid.UUID(result["current_credential_id"]))
    report = {
        "provider": provider,
        "model": model,
        "credential_id": credential_id,
        "changes": changes,
    }
    save_json(
        Path(state_dir) / ("model-limits-before-" + str(time.time_ns()) + ".json"),
        report,
    )
    for field, change in changes.items():
        credentials[field] = change["after"]
    # GET returns prefix + stars + suffix. That display mask is NOT the
    # keep-secret sentinel: sending it back would overwrite the real key.
    if credentials.get("api_key"):
        credentials["api_key"] = "[__HIDDEN__]"
    client.api(
        "PUT",
        path,
        {
            "model": model,
            "model_type": "llm",
            "credential_id": credential_id,
            "name": result.get("current_credential_name"),
            "credentials": credentials,
        },
    )
    return {"changed": True, "model": model, "changes": changes}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ApiError(req.method, code)


class Console:
    def __init__(self, base):
        url = urllib.parse.urlsplit(base)
        if (
            url.username
            or url.password
            or url.query
            or url.fragment
            or url.path.rstrip("/")
        ):
            raise Blocked(
                "Base URL must be an origin without credentials, path or query"
            )
        if url.scheme != "https" and not (
            url.scheme == "http" and url.hostname in {"127.0.0.1", "::1", "localhost"}
        ):
            raise Blocked("Credentials require HTTPS or a loopback HTTP endpoint")
        self.base = base.rstrip("/")
        self.cookies = {}
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect()
        )

    def request(self, method, path, data=None, *, stream=False, authenticated=True):
        if not path.startswith("/") or path.startswith("//"):
            raise Blocked("API path must be origin-relative")
        headers = {"Content-Type": "application/json"}
        if authenticated and self.cookies:
            headers["Cookie"] = "; ".join(k + "=" + v for k, v in self.cookies.items())
            headers["X-CSRF-Token"] = self.cookies.get(
                "__Host-csrf_token", self.cookies.get("csrf_token", "")
            )
        body = None if data is None else canonical(data).encode()
        request = urllib.request.Request(
            self.base + path, data=body, method=method, headers=headers
        )
        # Only read requests are retried. A create/update timeout is ambiguous.
        for attempt in range(3 if method == "GET" else 1):
            try:
                with self.opener.open(request, timeout=60) as response:
                    if authenticated:
                        for header in response.headers.get_all("Set-Cookie", []):
                            jar = http.cookies.SimpleCookie()
                            jar.load(header)
                            self.cookies.update({k: v.value for k, v in jar.items()})
                    payload = response.read(MAX_RESPONSE + 1)
                    if len(payload) > MAX_RESPONSE:
                        raise Blocked(
                            "API output exceeded limit; result is not accepted"
                        )
                    return payload.decode() if stream else json.loads(payload)
            except urllib.error.HTTPError as error:
                if (
                    method == "GET"
                    and attempt < 2
                    and (error.code == 429 or error.code >= 500)
                ):
                    time.sleep(2**attempt)
                    continue
                raise ApiError(method, error.code) from None
            except (urllib.error.URLError, TimeoutError, ConnectionError, OSError):
                raise ApiError(method) from None
            except (UnicodeDecodeError, json.JSONDecodeError):
                raise Blocked("Malformed API response; content suppressed") from None

    def api(self, method, path, data=None, **kwargs):
        return self.request(method, "/console/api" + path, data, **kwargs)

    def login(self, email, password_file):
        password = read_private(password_file).strip()
        response = self.api(
            "POST",
            "/login",
            {
                "email": email,
                "password": base64.b64encode(password.encode()).decode(),
                "remember_me": False,
            },
        )
        if response.get("result") != "success" or not self.cookies:
            raise Blocked("Console login did not establish a session")

    def inventory(self, tenant=None):
        profile = self.api("GET", "/account/profile")
        workspaces = self.api("GET", "/workspaces")["workspaces"]
        current = self.api("GET", "/workspaces/current/summary")
        if tenant and current.get("id") != tenant:
            raise Blocked(
                "Current workspace differs from --tenant; switch explicitly in Studio, then authenticate again"
            )
        if current.get("role") not in {"owner", "admin", "editor"}:
            raise Blocked("Current account cannot edit the target workspace")
        return {
            "account_id": profile["id"],
            "tenant_id": current["id"],
            "role": current["role"],
            "workspace_count": len(workspaces),
            "apps": self.list_resources("/apps"),
            "datasets": self.list_resources("/datasets"),
            "models": {
                kind: self.api(
                    "GET", "/workspaces/current/models/model-types/" + kind
                ).get("data", [])
                for kind in ("llm", "text-embedding", "rerank")
            },
        }

    def list_resources(self, path):
        resources = []
        for page in range(1, 101):
            result = self.api("GET", f"{path}?page={page}&limit=100")
            resources.extend(
                {k: item.get(k) for k in ("id", "name", "description", "mode")}
                for item in result.get("data", [])
            )
            if not result.get("has_more", len(resources) < result.get("total", 0)):
                return resources
        raise Blocked("Inventory exceeds safety limit; no resources selected")


def runtime_contract():
    def run(*args):
        try:
            return subprocess.run(
                args, check=True, capture_output=True, text=True, timeout=20
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            raise Blocked(
                "Cannot inspect running Dify containers; run remote commands on the target host with Podman access"
            ) from None

    images = {}
    for name, expected in DIGESTS.items():
        fields = run(
            "podman",
            "inspect",
            name,
            "--format",
            '{{.ImageDigest}}|{{index .Config.Labels "org.opencontainers.image.version"}}|{{index .Config.Labels "org.opencontainers.image.revision"}}',
        ).split("|")
        if fields != [expected, VERSION, REVISION]:
            raise Blocked(
                "Runtime image changed; inspect the installed contracts before adapting this importer"
            )
        images[name] = fields[0]
    installed = run("podman", "exec", "dify-api", "cat", "/app/api/pyproject.toml")
    schema = run(
        "podman", "exec", "dify-api", "cat", "/app/api/constants/dsl_version.py"
    )
    if (
        not re.search(r'^version = "1\.19\.0"$', installed, re.MULTILINE)
        or f'CURRENT_APP_DSL_VERSION = "{DSL_VERSION}"' not in schema
    ):
        raise Blocked("Installed package or DSL version differs from reviewed source")
    result = {
        "version": VERSION,
        "dsl_version": DSL_VERSION,
        "revision": REVISION,
        "images": images,
    }
    validate_runtime(result)
    return result


def validate_runtime(runtime):
    expected = {
        "version": VERSION,
        "dsl_version": DSL_VERSION,
        "revision": REVISION,
        "images": DIGESTS,
    }
    if runtime != expected:
        raise Blocked(
            "Runtime contract differs from the reviewed version, revision or image digests"
        )


def draft_content(draft):
    # Reviewed Dify 1.19 GET envelope; metadata is not part of the executable hash.
    if set(draft) - {
        "graph",
        "features",
        "conversation_variables",
        "environment_variables",
        "hash",
        "id",
        "created_at",
        "created_by",
        "updated_at",
        "updated_by",
        "marked_comment",
        "marked_name",
        "rag_pipeline_variables",
        "tool_published",
        "version",
        "version_number",
    }:
        raise Blocked("Unknown managed draft envelope fields")
    if draft.get("environment_variables"):
        raise Blocked("Managed fallback must not contain environment variables")
    if draft.get("rag_pipeline_variables"):
        raise Blocked("Managed draft must not contain RAG pipeline variables")
    # The draft GET response omits selectors, unlike the DSL export schema.
    for variable in draft.get("conversation_variables", []):
        if set(variable) - {
            "id",
            "name",
            "value_type",
            "value",
            "description",
            "selector",
        } or (
            "selector" in variable
            and variable["selector"] != ["conversation", variable.get("name")]
        ):
            raise Blocked("Unknown conversation variable fields or changed selector")
    variables = [
        {
            key: variable[key]
            for key in ("id", "name", "value_type", "value", "description")
        }
        for variable in draft.get("conversation_variables", [])
    ]
    return {
        "graph": draft["graph"],
        "features": draft["features"],
        "conversation_variables": variables,
    }


def execution_content(draft):
    """Remove only reviewed, typed Studio presentation fields; keep all else."""
    content = copy.deepcopy(draft_content(draft))
    # Dify 1.19 workflow-app/utils.ts buildInitialFeatures hydrates disabled uploads.
    # FileUploadConfigManager.convert gates actual advanced-chat files on enabled.
    upload = content["features"]["file_upload"]
    required = {
        "enabled",
        "allowed_file_types",
        "allowed_file_extensions",
        "allowed_file_upload_methods",
        "number_limits",
    }
    if (
        type(upload) is not dict
        or not required <= set(upload)
        or set(upload) - required - {"image", "fileUploadConfig"}
        or upload["enabled"] is not False
        or any(
            type(upload[key]) is not list or upload[key]
            for key in (
                "allowed_file_types",
                "allowed_file_extensions",
                "allowed_file_upload_methods",
            )
        )
        or type(upload["number_limits"]) is not int
        or upload["number_limits"] not in (0, 3)
    ):
        raise Blocked("Unreviewed or enabled file upload settings")
    upload["number_limits"] = 0
    if "image" in upload:
        image = upload.pop("image")
        if (
            type(image) is not dict
            or set(image) != {"enabled", "number_limits", "transfer_methods"}
            or image["enabled"] is not False
            or type(image["number_limits"]) is not int
            or image["number_limits"] != 3
            or type(image["transfer_methods"]) is not list
            or image["transfer_methods"] != ["local_file", "remote_url"]
        ):
            raise Blocked("Unreviewed or enabled image upload settings")
    if "fileUploadConfig" in upload:
        config = upload.pop("fileUploadConfig")
        limits = {
            "file_size_limit": 15,
            "knowledge_file_size_limit": 15,
            "batch_count_limit": 5,
            "file_upload_limit": 20,
            "image_file_size_limit": 10,
            "video_file_size_limit": 100,
            "audio_file_size_limit": 50,
            "skill_file_size_limit": 50,
            "workflow_file_upload_limit": 10,
            "image_file_batch_limit": 10,
            "single_chunk_attachment_limit": 10,
            "attachment_image_file_size_limit": 2,
        }
        if (
            type(config) is not dict
            or set(config) != set(limits)
            or any(
                type(config[key]) is not int or config[key] != value
                for key, value in limits.items()
            )
        ):
            raise Blocked("Unreviewed Studio file upload limits")
    graph = content["graph"]

    def number(value, low=-10_000_000, high=10_000_000):
        if type(value) not in (int, float) or not low <= value <= high:
            raise Blocked("Invalid Studio UI numeric field")

    def point(value):
        if type(value) is not dict or set(value) != {"x", "y"}:
            raise Blocked("Invalid Studio UI position fields")
        for coordinate in value.values():
            number(coordinate)

    viewport = graph.pop("viewport")
    if type(viewport) is not dict or set(viewport) != {"x", "y", "zoom"}:
        raise Blocked("Invalid Studio UI viewport fields")
    point({key: viewport[key] for key in ("x", "y")})
    number(viewport["zoom"], 0.01, 100)
    nodes = {node["id"]: node for node in graph["nodes"]}
    if len(nodes) != len(graph["nodes"]):
        raise Blocked("Duplicate managed node IDs")
    positions = {key: copy.deepcopy(node["position"]) for key, node in nodes.items()}
    for node in nodes.values():
        data = node["data"]
        point(node.pop("position"))
        for field in ("width", "height"):
            number(node.pop(field), 1, 100_000)
            if field in data:
                if data.get("type") != "iteration":
                    raise Blocked("Unexpected Studio node dimensions")
                number(data.pop(field), 1, 100_000)
        title = data.pop("title")
        if type(title) is not str or len(title) > 1000:
            raise Blocked("Invalid Studio UI title")
        for holder in (node, data):
            if "selected" in holder and type(holder.pop("selected")) is not bool:
                raise Blocked("Invalid Studio UI selection")
        inside = node.get("parentId") == "kg_iteration"
        if "zIndex" in node:
            z_index = node.pop("zIndex")
            if type(z_index) is not int or z_index != (1001 if inside else 0):
                raise Blocked("Unexpected Studio node zIndex")
        if "positionAbsolute" in node:
            absolute = node.pop("positionAbsolute")
            point(absolute)
            parent = positions["kg_iteration"] if inside else {"x": 0, "y": 0}
            if any(
                absolute[key] != positions[node["id"]][key] + parent[key]
                for key in ("x", "y")
            ):
                raise Blocked("Studio absolute position is not derived from layout")
    edge_ids = set()
    for edge in graph["edges"]:
        if edge["id"] in edge_ids:
            raise Blocked("Duplicate managed edge IDs")
        edge_ids.add(edge["id"])
        source, target = nodes[edge["source"]], nodes[edge["target"]]
        inside = all(
            node.get("parentId") == "kg_iteration"
            and node["data"].get("iteration_id") == "kg_iteration"
            and node["data"].get("isInIteration") is True
            for node in (source, target)
        )
        if "zIndex" in edge:
            z_index = edge.pop("zIndex")
            if type(z_index) is not int or z_index != (1001 if inside else 0):
                raise Blocked("Unexpected Studio edge zIndex")
        if "iteration_id" in edge["data"] and (
            not inside
            or edge["data"].get("isInIteration") is not True
            or edge["data"].pop("iteration_id") != "kg_iteration"
        ):
            raise Blocked("Unexpected Studio iteration edge annotation")
    return content


def merge_ui_draft(generated, current, desired):
    if digest(execution_content(generated)) != digest(execution_content(current)):
        raise Blocked("Executable or unknown draft edits; refusing to overwrite")
    merged = copy.deepcopy(desired)
    missing = object()

    def overlay(old, edited, target, fields):
        for field in fields:
            if old.get(field, missing) != edited.get(field, missing):
                if target.get(field, missing) != old.get(field, missing) and target.get(
                    field, missing
                ) != edited.get(field, missing):
                    raise Blocked("Divergent Studio UI edits; refusing to overwrite")
                if field in edited:
                    target[field] = copy.deepcopy(edited[field])
                else:
                    target.pop(field, None)

    old_graph, ui_graph, graph = (
        item["graph"] for item in (generated, current, merged)
    )
    overlay(old_graph, ui_graph, graph, ("viewport",))
    overlay(
        generated["features"]["file_upload"],
        current["features"]["file_upload"],
        merged["features"]["file_upload"],
        ("number_limits", "image", "fileUploadConfig"),
    )
    for kind, fields, data_fields in (
        (
            "nodes",
            ("position", "positionAbsolute", "width", "height", "zIndex", "selected"),
            ("title", "selected", "width", "height"),
        ),
        ("edges", ("zIndex",), ("iteration_id",)),
    ):
        old = {item["id"]: item for item in old_graph[kind]}
        edited = {item["id"]: item for item in ui_graph[kind]}
        for target in graph[kind]:
            key = target["id"]
            if key in old:
                overlay(old[key], edited[key], target, fields)
                overlay(
                    old[key]["data"], edited[key]["data"], target["data"], data_fields
                )
    # Recompute the derived coordinates if generator layout changed untouched nodes.
    nodes = {node["id"]: node for node in graph["nodes"]}
    for node in nodes.values():
        if "positionAbsolute" in node:
            parent = (
                nodes[node["parentId"]]["position"]
                if node.get("parentId")
                else {"x": 0, "y": 0}
            )
            node["positionAbsolute"] = {
                key: node["position"][key] + parent[key] for key in ("x", "y")
            }
    if digest(execution_content(merged)) != digest(execution_content(desired)):
        raise Blocked("Merged execution differs from generated graph")
    return merged


def draft_baseline(generated, applied):
    generated, applied = (draft_content(item) for item in (generated, applied))
    if digest(execution_content(generated)) != digest(execution_content(applied)):
        raise Blocked("Applied baseline differs from generated execution")
    return {
        "generated": generated,
        "applied": applied,
        "generated_sha256": digest(generated),
        "applied_sha256": digest(applied),
    }


def load_baseline(state_dir, state):
    baseline = state.get("draft_baseline")
    if baseline is None:
        # Migration is hash-anchored to the actual old artifact, never today's build.
        recovery = json.loads(read_private(Path(state_dir) / "recovery-bundle.json"))
        if (
            digest(recovery["manifest"]) != state.get("bundle_sha256")
            or digest(recovery["dsl"]) != recovery["manifest"]["dsl_sha256"]
        ):
            raise Blocked("Recovery bundle hash does not match managed state")
        baseline = draft_baseline(
            recovery["dsl"]["workflow"], recovery["dsl"]["workflow"]
        )
    if baseline != draft_baseline(
        baseline["generated"], baseline["applied"]
    ) or baseline["applied_sha256"] != state.get("draft_sha256"):
        raise Blocked("Draft baseline hash does not match managed state")
    return baseline["generated"]


def finish_draft_save(client, state_dir, state, current, *, resume=True):
    """Resume exactly one durable save intent, without rebuilding or helper writes."""
    recovery = json.loads(read_private(state_dir / "recovery-bundle.json"))
    if digest(recovery) != state.get("pending_recovery_sha256"):
        raise Blocked("Pending recovery bundle hash mismatch")
    desired = recovery["desired"]
    desired_hash = digest(draft_content(desired))
    if (
        recovery["app_id"] != state["app_id"]
        or recovery["tenant_id"] != state["tenant_id"]
        or recovery["origin"] != state["origin"]
        or desired_hash != state["pending_draft_sha256"]
        or digest(recovery["manifest"]) != state["pending_bundle_sha256"]
        or digest(recovery["dsl"]) != recovery["manifest"]["dsl_sha256"]
    ):
        raise Blocked("Pending recovery identity or draft hash mismatch")
    baseline = draft_baseline(recovery["dsl"]["workflow"], desired)
    current_hash = digest(draft_content(current)) if current else None
    changed = not resume or current_hash != desired_hash
    if changed:
        if (
            current_hash != recovery["base_draft_sha256"]
            or (current.get("hash") if current else None) != recovery["server_hash"]
        ):
            raise Blocked(
                "Draft changed since frozen save intent; refusing to overwrite"
            )
        result = client.api(
            "POST",
            f"/apps/{state['app_id']}/workflows/draft",
            {**desired, "hash": recovery["server_hash"]},
        )
        current = get_draft(client, state["app_id"])
        if current is None or result.get("hash") != current.get("hash"):
            raise Blocked("Server hash changed during draft readback")
    if (
        current is None
        or not current.get("hash")
        or digest(draft_content(current)) != desired_hash
    ):
        raise Blocked(
            "Saved graph differs from the frozen draft; inspect before accepting"
        )
    check_private(client, state["app_id"])
    state.update(
        phase="ready",
        draft_sha256=desired_hash,
        bundle_sha256=state["pending_bundle_sha256"],
        draft_baseline=baseline,
    )
    for key in (
        "pending_draft_sha256",
        "pending_bundle_sha256",
        "pending_recovery_sha256",
    ):
        state.pop(key, None)
    save_json(state_dir / "state.json", state)
    return {
        "changed": changed,
        "app_id": state["app_id"],
        "tenant_id": state["tenant_id"],
        "configured_teacher_count": len(recovery["manifest"]["teacher_directory"]),
        "requires_live_acceptance": True,
        "preview": "https://chat.dora.im/app/" + state["app_id"] + "/workflow",
        "published": False,
    }


def get_draft(client, app_id):
    try:
        return client.api("GET", f"/apps/{app_id}/workflows/draft")
    except ApiError as error:
        if error.status == 404:
            return None
        raise


def check_private(client, app_id):
    detail = client.api("GET", "/apps/" + app_id)
    if detail.get("enable_site") is not False or detail.get("enable_api") is not False:
        raise Blocked(
            "Managed app has a public site/API enabled; disabling is required before use"
        )
    if detail.get("workflow"):
        raise Blocked(
            "Managed app has a published workflow; this tool only manages unpublished Studio drafts"
        )
    return detail


def apply(
    client,
    tenant,
    data,
    state_dir,
    runtime,
    *,
    binding=None,
    merge_ui_only=False,
    repair_limits=False,
):
    validate_runtime(runtime)
    dsl, manifest = bundle(data, binding)
    state_dir = private_dir(state_dir)
    state_path = state_dir / "state.json"
    lock_fd = os.open(state_dir / "lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock_fd, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Blocked("Another apply holds the runtime lock") from None
        if merge_ui_only and not state_path.exists():
            raise Blocked(
                "--merge-ui-only requires existing managed app state; never creates an app"
            )
        inventory = client.inventory(tenant)
        if state_path.exists():
            state = json.loads(read_private(state_path))
            if state.get("tenant_id") != tenant or state.get("origin") != client.base:
                raise Blocked("Runtime state belongs to another tenant or origin")
            if state.get("account_id") != inventory["account_id"]:
                raise Blocked("Runtime state belongs to another account")
            if merge_ui_only and (
                not state.get("app_id")
                or not state.get("draft_sha256")
                or state.get("phase") not in {"ready", "saving"}
            ):
                raise Blocked("--merge-ui-only requires an existing managed draft")
        else:
            state = {
                "schema_version": 1,
                "tenant_id": tenant,
                "account_id": inventory["account_id"],
                "origin": client.base,
                "marker": "dify-kaogong:" + str(uuid.uuid4()),
                "phase": "reserved",
                "created_resources": [],
                "runtime": runtime,
            }
            save_json(state_path, state)
        if state["phase"] == "reserved":
            save_json(
                state_dir / "recovery-bundle.json",
                {"dsl": dsl, "manifest": manifest, "catalog": data},
            )
            # Persist the creation intent before the non-idempotent request.
            state["phase"] = "creating"
            save_json(state_path, state)
            # Do not retry creation, even on 429/5xx. Resume reconciles by a unique marker.
            result = client.api(
                "POST",
                "/apps",
                {
                    "name": APP_NAME,
                    "mode": "advanced-chat",
                    "description": state["marker"],
                    "icon_type": "emoji",
                    "icon": "K",
                    "icon_background": "#E8E2D5",
                },
            )
            state["app_id"] = str(uuid.UUID(result["id"]))
            state["created_resources"] = [{"kind": "app", "id": state["app_id"]}]
            state["phase"] = "created"
            save_json(state_path, state)

        if not state.get("app_id"):
            matches = [
                app
                for app in client.list_resources("/apps")
                if app.get("description") == state["marker"]
            ]
            if len(matches) != 1:
                raise Blocked(
                    "Uncertain app creation: no unique managed marker found; inspect Studio before resolving state, do not blindly retry"
                )
            state["app_id"] = str(uuid.UUID(matches[0]["id"]))
            state["created_resources"] = [{"kind": "app", "id": state["app_id"]}]
            state["phase"] = "created"
            save_json(state_path, state)
        app_id = str(uuid.UUID(state["app_id"]))
        detail = client.api("GET", "/apps/" + app_id)
        if (
            detail.get("description") != state["marker"]
            or detail.get("mode") != "advanced-chat"
        ):
            raise Blocked("Managed app identity changed; refusing to overwrite it")
        if detail.get("workflow"):
            raise Blocked("Managed app was published; refusing to change it")

        # A fresh empty app has no runnable published workflow. Disable both entry points before installing code.
        if state["phase"] == "created":
            if get_draft(client, app_id) is not None:
                raise Blocked(
                    "Unexpected draft before first save; another editor changed the newly created app"
                )
            for field, endpoint in (
                ("enable_site", "site-enable"),
                ("enable_api", "api-enable"),
            ):
                client.api("POST", f"/apps/{app_id}/{endpoint}", {field: False})
            check_private(client, app_id)
            state["draft_sha256"] = None
            state["phase"] = "private"
            save_json(state_path, state)
        check_private(client, app_id)
        current = get_draft(client, app_id)
        current_hash = digest(draft_content(current)) if current else None

        if current is not None and (
            type(current.get("hash")) is not str or not current["hash"]
        ):
            raise Blocked("Managed draft is missing its server concurrency hash")
        if state["phase"] == "saving":
            return finish_draft_save(client, state_dir, state, current)
        if current_hash != state.get("draft_sha256") and not merge_ui_only:
            raise Blocked(
                "User-edited or concurrently changed managed draft; refusing to overwrite"
            )
        generated = None
        if merge_ui_only or state.get("draft_baseline"):
            if current is None:
                raise Blocked("Managed draft is missing; refusing to overwrite")
            generated = load_baseline(state_dir, state)
            # Check all drift before any knowledge or credential helper can write.
            merge_ui_draft(generated, current, dsl["workflow"])

        before_state = copy.deepcopy(state)
        if repair_limits:
            chosen = binding or state.get("binding") or default_binding(data)
            repair_model_limits(client, chosen["provider"], chosen["model"], state_dir)
        methods = [m for m in data["methods"]["methods"] if m["status"] == "approved"]
        if methods:
            binding = dict(binding or state.get("binding") or default_binding(data))
            if merge_ui_only:
                owned = copy.deepcopy(state.get("knowledge", {}).get("current") or {})
                if (
                    owned.get("dataset_id")
                    != state.get("binding", {}).get("dataset_id")
                    or not owned.get("dataset_id")
                    or {
                        key: item["content_hash"]
                        for key, item in owned.get("documents", {}).items()
                    }
                    != {
                        method["skill_id"]: method["content_hash"] for method in methods
                    }
                ):
                    raise Blocked(
                        "UI merge requires unchanged existing managed knowledge resources"
                    )
            available = any(
                provider.get("provider") == binding["provider"]
                and any(
                    model.get("model") == binding["model"]
                    and model.get("status") == "active"
                    for model in provider.get("models", [])
                )
                for provider in inventory["models"]["llm"]
            )
            if not available:
                raise Blocked(
                    "Selected model is absent/inactive in this workspace; preserve credentials and configure a working model first"
                )
            try:
                knowledge = knowledge_module().ensure_knowledge(
                    client,
                    tenant,
                    methods,
                    state,
                    lambda value: save_json(state_path, value),
                    token_file=state_dir / "knowledge-api-key",
                )
            except RuntimeError as error:
                raise Blocked(str(error)) from None
            if merge_ui_only and knowledge != owned:
                raise Blocked("Managed knowledge changed during UI merge")
            binding.update(
                dataset_id=knowledge["dataset_id"],
                retrieval_top_k=knowledge["retrieval_top_k"],
            )
            dsl, manifest = bundle(data, binding)
            state["binding"] = binding
            resources = [{"kind": "dataset", "id": knowledge["dataset_id"]}]
            resources.extend(
                {
                    "kind": "document",
                    "id": item["document_id"],
                    "dataset_id": knowledge["dataset_id"],
                }
                for item in knowledge["documents"].values()
            )
            for resource in resources:
                if resource not in state["created_resources"]:
                    state["created_resources"].append(resource)
            save_json(state_path, state)
            save_json(state_dir / "binding.json", binding)
        desired = {
            key: dsl["workflow"][key]
            for key in ("graph", "features", "conversation_variables")
        }
        if generated is not None:
            desired = merge_ui_draft(generated, current, desired)
        desired_hash = digest(draft_content(desired))
        write_bundle(state_dir / "build", dsl, manifest, data)

        latest = get_draft(client, app_id)
        if (digest(draft_content(latest)) if latest else None) != current_hash or (
            latest.get("hash") if latest else None
        ) != (current.get("hash") if current else None):
            raise Blocked("Managed draft changed during apply; refusing to overwrite")
        if (
            state.get("bundle_sha256") == digest(manifest)
            and state["phase"] == "ready"
            and desired_hash == current_hash
        ):
            if current_hash != state.get("draft_sha256"):
                state.update(
                    draft_sha256=current_hash,
                    draft_baseline=draft_baseline(dsl["workflow"], current),
                )
                save_json(state_path, state)
            return {
                "changed": False,
                "app_id": app_id,
                "tenant_id": tenant,
                "configured_teacher_count": len(manifest["teacher_directory"]),
                "requires_live_acceptance": True,
            }

        backup_id = str(time.time_ns())
        save_json(
            state_dir / ("before-" + backup_id + ".json"),
            {
                "tenant_id": tenant,
                "app_id": app_id,
                "draft": draft_content(current) if current else None,
                "server_hash": current.get("hash") if current else None,
                "state": before_state,
                "datasets": inventory["datasets"],
            },
        )
        recovery = {
            "dsl": dsl,
            "manifest": manifest,
            "catalog": data,
            "desired": desired,
            "app_id": app_id,
            "tenant_id": tenant,
            "origin": client.base,
            "base_draft_sha256": current_hash,
            "server_hash": current.get("hash") if current else None,
        }
        # Preserve the accepted old baseline before replacing its legacy recovery file.
        if generated is not None and not state.get("draft_baseline"):
            state["draft_baseline"] = draft_baseline(generated, generated)
            save_json(state_path, state)
        save_json(state_dir / "recovery-bundle.json", recovery)
        state.update(
            phase="saving",
            pending_draft_sha256=desired_hash,
            pending_bundle_sha256=digest(manifest),
            pending_recovery_sha256=digest(recovery),
            runtime=runtime,
        )
        save_json(state_path, state)
        return finish_draft_save(
            client, state_dir, state, get_draft(client, app_id), resume=False
        )


def preview(client, app_id, query, conversation_id=None):
    payload = {"query": query, "inputs": {}, "files": []}
    if conversation_id:
        payload["conversation_id"] = conversation_id
    text = client.api(
        "POST",
        f"/apps/{app_id}/advanced-chat/workflows/draft/run",
        payload,
        stream=True,
    )
    answer, conversation, finished, succeeded = "", None, False, False
    teachers = []
    node_statuses = []
    workflow_result = None
    for line in text.splitlines():
        if not line.startswith("data:"):
            continue
        try:
            event = json.loads(line[5:])
        except json.JSONDecodeError:
            raise Blocked("Truncated or malformed preview event") from None
        if not isinstance(event, dict) or not isinstance(event.get("event"), str):
            raise Blocked("Malformed preview event schema")
        if event["event"] == "workflow_finished" and not isinstance(
            event.get("data"), dict
        ):
            raise Blocked("Malformed preview workflow status")
        if event.get("event") == "error" or (
            event.get("event") == "workflow_finished"
            and event.get("data", {}).get("status")
            not in {"succeeded", "partial-succeeded"}
        ):
            raise Blocked(
                "Studio preview workflow failed; inspect authenticated node traces (response suppressed)"
            )
        if event.get("event") in {"message", "agent_message"}:
            if not isinstance(event.get("answer"), str):
                raise Blocked("Malformed preview answer schema")
            answer += event["answer"]
        if event.get("event") == "node_finished":
            if not isinstance(event.get("data"), dict):
                raise Blocked("Malformed preview node status")
            node = event["data"]
            node_statuses.append((node.get("node_id"), node.get("status")))
            if node.get("node_id") == "kg_verify":
                item = node.get("outputs", {}).get("result", {})
                if isinstance(item, dict):
                    teachers.append(
                        {
                            "teacher_id": item.get("teacher_id"),
                            "status": item.get("status"),
                        }
                    )
        if event.get("event") == "workflow_finished":
            succeeded = True
            workflow_result = event["data"]
        if event.get("conversation_id"):
            try:
                incoming_id = str(uuid.UUID(event["conversation_id"]))
            except (ValueError, TypeError, AttributeError):
                raise Blocked("Malformed preview conversation ID") from None
            if conversation and conversation != incoming_id:
                raise Blocked("Preview stream mixed different conversations")
            conversation = incoming_id
        if event.get("event") == "message_end":
            finished = True
    if not finished or not succeeded or not conversation or not answer:
        raise Blocked("Incomplete Studio preview stream; no result accepted")
    if conversation_id and conversation != conversation_id:
        raise Blocked("Preview follow-up returned a different conversation")
    result = {"answer": answer, "conversation_id": conversation}
    if workflow_result["status"] == "partial-succeeded":
        # Dify counts recovered retry attempts as exceptions in the run summary.
        # Never accept unresolved node failures, missing final gates or default fallbacks.
        if (
            not node_statuses
            or any(status != "succeeded" for _, status in node_statuses)
            or not {"kg_render", "kg_answer"} <= {key for key, _ in node_statuses}
            or type(workflow_result.get("exceptions_count")) is not int
            or workflow_result["exceptions_count"] < 1
            or workflow_result.get("error")
        ):
            raise Blocked("Studio preview has unresolved failures; no result accepted")
        result["workflow_status"] = "partial-succeeded"
        result["recovered_exceptions"] = workflow_result["exceptions_count"]
    if teachers:
        result["teachers"] = teachers
    return result


def verify_teachers(client, tenant, state, state_dir):
    data = load_assets()
    methods = [m for m in data["methods"]["methods"] if m["status"] == "approved"]
    try:
        retrieval = knowledge_module().verify_retrieval(
            client,
            tenant,
            state["knowledge"]["current"],
            methods,
            token_file=Path(state_dir) / "knowledge-api-key",
        )
    except RuntimeError as error:
        raise Blocked(str(error)) from None
    cases = [
        (
            "summary-comparison",
            "概括维修服务存在的问题，不超过80字。材料：报修登记后无人告知办理进度。热线与网站重复登记同一事项。夜间无人接听报修电话。",
            {"li-mengyuan", "yuan-dong"},
            ("李梦圆", "袁东"),
        ),
        (
            "option-substitution",
            "整数x、y均非负，x+y=7，2x+3y=18。求x。选项A=1、B=2、C=3、D=4。",
            {"honglingjin"},
            ("红领巾", "3"),
        ),
        (
            "material-proposals",
            next(
                m["examples"][0]["input"]
                for m in methods
                if m["skill_id"] == "bailu.material-proposals"
            ),
            {"bailu"},
            ("白鹭",),
        ),
        (
            "essay-outline",
            next(
                m["examples"][0]["input"]
                for m in methods
                if m["skill_id"] == "bailu.essay-topic-decomposition"
            ),
            {"bailu"},
            ("白鹭",),
        ),
        (
            "general-growth",
            "某企业现期收入5000万元，同比增长12.5%，增长额是多少？",
            set(),
            ("通用解法", "555.56"),
        ),
    ]
    checked = []
    summary_conversation = None
    for name, question, expected_teachers, text in cases:
        result = preview(client, state["app_id"], question)
        answered = {
            item["teacher_id"]
            for item in result.get("teachers", [])
            if item["status"] == "answered"
        }
        if answered != expected_teachers or not all(
            part in result["answer"] for part in text
        ):
            raise Blocked(
                "Real teacher/model acceptance failed at "
                + name
                + "; a fallback or error message is not a passing answer"
            )
        if name == "summary-comparison":
            summary_conversation = result["conversation_id"]
        checked.append(
            {
                "case": name,
                "passed": True,
                "teacher_ids": sorted(answered),
                "workflow_status": result.get("workflow_status", "succeeded"),
                "recovered_exceptions": result.get("recovered_exceptions", 0),
            }
        )
    followup = preview(client, state["app_id"], "展开第二位老师", summary_conversation)
    if {
        item["teacher_id"]
        for item in followup.get("teachers", [])
        if item["status"] == "answered"
    } != {"li-mengyuan", "yuan-dong"}:
        raise Blocked(
            "Teacher follow-up failed to preserve the original question and all matching teachers"
        )
    missing = preview(
        client, state["app_id"], "请概括材料中的主要问题，但我还没提供材料。"
    )
    if (
        any(item["status"] == "answered" for item in missing.get("teachers", []))
        or "材料" not in missing["answer"]
    ):
        raise Blocked("Missing-material refusal failed")
    return {
        "app_id": state["app_id"],
        "anonymous_denied": True,
        "retrieval": retrieval,
        "preview_cases": checked,
        "followup_passed": True,
        "missing_material_passed": True,
        "verified_teacher_count": 4,
        "real_teacher_comparisons": 1,
        "status": "passed",
    }


def verify_remote(client, tenant, state_dir):
    state = json.loads(read_private(Path(state_dir) / "state.json"))
    if (
        state.get("tenant_id") != tenant
        or state.get("origin") != client.base
        or state.get("phase") != "ready"
    ):
        raise Blocked("No ready managed app for this tenant/origin")
    inventory = client.inventory(tenant)
    if inventory["account_id"] != state.get("account_id"):
        raise Blocked("Verification account differs from runtime owner")
    app_id = str(uuid.UUID(state["app_id"]))
    detail = check_private(client, app_id)
    if (
        detail.get("description") != state["marker"]
        or detail.get("mode") != "advanced-chat"
    ):
        raise Blocked("Managed app identity changed")
    current = get_draft(client, app_id)
    if current is None:
        raise Blocked("Managed draft is missing")
    if digest(draft_content(current)) != state.get("draft_sha256"):
        generated = load_baseline(state_dir, state)
        merge_ui_draft(generated, current, generated)
    # Check the real WebApp passport path without any console cookies.
    code = detail.get("site", {}).get("code")
    if not code or not re.fullmatch(r"[A-Za-z0-9_-]+", code):
        raise Blocked(
            "Cannot determine the managed WebApp code for anonymous denial test"
        )
    for headers, expected_status, expected_code in (
        ({}, 401, "unauthorized"),
        ({"X-App-Code": code}, 404, "app_not_found"),
    ):
        request = urllib.request.Request(client.base + "/api/passport", headers=headers)
        try:
            with client.opener.open(request, timeout=20):
                raise Blocked("Anonymous WebApp passport was not denied")
        except urllib.error.HTTPError as error:
            try:
                body = json.loads(error.read(4096))
            except (ValueError, UnicodeDecodeError):
                raise Blocked(
                    "Anonymous probe returned an unrecognized error"
                ) from None
            if (
                error.code != expected_status
                or body.get("code") != expected_code
                or body.get("status") != expected_status
            ):
                raise Blocked("Anonymous probe was inconclusive") from None
            if not headers and body.get("message") != "X-App-Code header is missing.":
                raise Blocked("Anonymous passport route contract changed")
    if state.get("binding"):
        return verify_teachers(client, tenant, state, state_dir)
    no_match = load_module("nodes").NO_MATCH
    cases = [
        (
            "现期量5000，增长率12.5%，求基期量和增长量。",
            (no_match, "4444.44", "555.56"),
        ),
        ("请根据材料写申论，但我还没提供材料。", (no_match,)),
        ("截图看不清，帮我选正确答案。", (no_match,)),
    ]
    checked = []
    conversation = None
    growth_conversation = None
    for query, expected in cases:
        result = preview(client, app_id, query)
        if not all(part in result["answer"] for part in expected):
            raise Blocked("Representative preview answer failed acceptance")
        conversation = result["conversation_id"]
        if growth_conversation is None:
            growth_conversation = conversation
        checked.append({"query": query, "passed": True})
    arithmetic_followup = preview(client, app_id, "为什么不是625", growth_conversation)
    if not all(
        part in arithmetic_followup["answer"]
        for part in (no_match, "4444.44", "555.56")
    ):
        raise Blocked(
            "Arithmetic follow-up failed to preserve and recompute the question"
        )
    followup = preview(client, app_id, "展开第二位老师", conversation)
    if no_match not in followup["answer"]:
        raise Blocked("Follow-up fabricated a teacher")
    return {
        "app_id": app_id,
        "anonymous_denied": True,
        "preview_cases": checked,
        "followup_passed": True,
        "arithmetic_followup_passed": True,
        "real_teacher_comparisons": 0,
        "model_calls": 0,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "build", "apply", "verify"))
    parser.add_argument(
        "--remote",
        action="store_true",
        help="Authenticate; verify also runs Studio previews and creates debug records",
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:5001")
    parser.add_argument("--email")
    parser.add_argument("--password-file", type=Path)
    parser.add_argument(
        "--tenant", help="Explicit workspace UUID; no automatic switching"
    )
    parser.add_argument(
        "--state-dir", type=Path, default=Path("/var/lib/dify/kaogong-teachers")
    )
    parser.add_argument("--output", type=Path, help="Private local build directory")
    parser.add_argument(
        "--binding-file",
        type=Path,
        help="Nonsecret dataset/model binding JSON; apply always resolves its own managed dataset",
    )
    parser.add_argument(
        "--merge-ui-only",
        action="store_true",
        help="apply only: preserve validated Studio UI edits on the existing managed app",
    )
    parser.add_argument(
        "--repair-model-limits",
        action="store_true",
        help="apply only: normalize commas in the selected model's numeric limits without replacing its key",
    )
    args = parser.parse_args(argv)
    try:
        data = load_assets()
        binding = (
            json.loads(args.binding_file.read_text()) if args.binding_file else None
        )
        if args.repair_model_limits and args.command != "apply":
            raise Blocked("--repair-model-limits is only permitted with explicit apply")
        if args.merge_ui_only and args.command != "apply":
            raise Blocked("--merge-ui-only is only permitted with explicit apply")
        if args.command == "build":
            if args.remote or not args.output:
                raise Blocked("build is offline and requires --output")
            dsl, manifest = bundle(data, binding)
            write_bundle(args.output, dsl, manifest, data)
            result = {
                "output": str(args.output),
                "requires_binding": manifest["requires_binding"],
                **summary(data),
            }
        elif args.command == "apply" or args.remote:
            if not args.email or not args.password_file or not args.tenant:
                raise Blocked(
                    "Remote operations require --email, --password-file and --tenant"
                )
            uuid.UUID(args.tenant)
            if args.base_url != "http://127.0.0.1:5001":
                raise Blocked(
                    "Runtime inspection is local: use fra0's reviewed loopback API http://127.0.0.1:5001"
                )
            runtime = runtime_contract()
            client = Console(args.base_url)
            client.login(args.email, args.password_file)
            if args.command == "apply":
                result = apply(
                    client,
                    args.tenant,
                    data,
                    args.state_dir,
                    runtime,
                    binding=binding,
                    merge_ui_only=args.merge_ui_only,
                    repair_limits=args.repair_model_limits,
                )
            elif args.command == "verify":
                try:
                    result = verify_remote(client, args.tenant, args.state_dir)
                except Blocked as error:
                    save_json(
                        args.state_dir / "verification.json",
                        {"status": "failed", "reason": str(error)},
                    )
                    raise
                else:
                    save_json(args.state_dir / "verification.json", result)
            else:
                inventory = client.inventory(args.tenant)
                result = {
                    **summary(data),
                    "runtime": runtime,
                    "tenant_id": inventory["tenant_id"],
                    "role": inventory["role"],
                    "workspace_count": inventory["workspace_count"],
                    "app_count": len(inventory["apps"]),
                    "dataset_count": len(inventory["datasets"]),
                    "model_provider_counts": {
                        k: len(v) for k, v in inventory["models"].items()
                    },
                }
        elif args.command == "verify":
            failed = False
            for test in sorted((ROOT / "tests").glob("test-dify-kaogong*.py")):
                completed = subprocess.run(
                    [sys.executable, "-B", str(test)], check=False
                )
                failed = failed or completed.returncode != 0
            return int(failed)
        else:
            bundle(data, binding)
            result = {"offline_validation": "passed", **summary(data)}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except Blocked as error:
        print("BLOCKED: " + str(error), file=sys.stderr)
        return 2
    except (OSError, ValueError, KeyError, TypeError):
        print(
            "BLOCKED: invalid local asset, state, argument or API schema; details suppressed",
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    raise SystemExit(main())
