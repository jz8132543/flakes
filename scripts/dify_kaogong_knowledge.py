"""Native Dify 1.19.0 knowledge import, called only by the explicit apply path.

The caller validates the catalog/runtime and holds the runtime-state lock.
save_state(state) must durably save the entire shared state before returning.
Only state['knowledge'] is modified. Keys live in memory or a private runtime
file, never in state, returned mappings, logs, or exception messages.

Changed catalogs use immutable dataset generations: the previous graph and its
dataset remain untouched until the caller switches the graph. No DELETE,
document replacement, metadata rename, or unrelated resource update is used.
An ambiguous create is reconciled by its persisted UUID marker, never reposted.
An ambiguous reveal-once key creation requires operator recovery, not a new key.

Installed source contracts: controllers/service_api/dataset/{dataset,document,
metadata,hit_testing}.py; controllers/console/datasets/datasets.py;
services/knowledge/entities/knowledge_entities.py; services/hit_testing_service.py.
The native splitter counts characters, despite the max_tokens field name.
Economy Jieba ranks globally BEFORE filtering, so top_k covers the entire
immutable generation (one verified segment per document), not one teacher.
Public retrieve tests write native query audit records; they are not dry runs.
Pending economy generations receive deterministic teaching-text keywords before
acceptance. These are lexical recall aids, not evidence of semantic relevance.
Keyword-only updates preserve card content and snapshot both old/new keyword
lists; accepted generations never receive an unrecorded strategy change.
"""

from __future__ import annotations

import copy
import functools
import hashlib
import json
import os
import re
import stat
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

_FIELDS = ("teacher_id", "skill_id", "topic_id", "status", "content_hash")
_MAX_RESPONSE = 8 * 1024 * 1024
_MAX_CHARS = 4000
_SEPARATOR = "__KAOGONG_COMPLETE_METHOD_BOUNDARY__"
_KEYWORD_STRATEGY = "teaching-ascii-cjk2-6-v1"
_MAX_KEYWORDS = 4096
_MAX_KEYWORD_CHARS = 128


class _Error(RuntimeError):
    """Safe to print; never constructed from a response body or secret."""


def _safe(function):
    @functools.wraps(function)
    def call(*args, **kwargs):
        try:
            return function(*args, **kwargs)
        except _Error:
            raise
        except Exception:  # noqa: BLE001 - public boundary must suppress credential-bearing errors.
            raise _Error(
                "Knowledge operation failed; local/API details suppressed"
            ) from None

    return call


def _canonical(value):
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def _digest(value):
    return hashlib.sha256(_canonical(value).encode()).hexdigest()


def _keyword_values(value):
    if value is None:
        return []
    if (
        type(value) is not list
        or len(value) > _MAX_KEYWORDS
        or any(
            type(word) is not str or not 1 <= len(word) <= _MAX_KEYWORD_CHARS
            for word in value
        )
    ):
        raise _Error(
            "Keyword list exceeds 4096 entries or 128 characters per entry; no truncation allowed"
        )
    return value


def _teaching_keywords(method):
    # Exclude JSON field names, provenance and English audit boilerplate.
    text = "\n".join(
        [
            method["name"],
            *method["steps"],
            *[example["input"] for example in method["examples"]],
        ]
    )
    if len(text) > _MAX_CHARS:
        raise _Error("Teaching keyword input exceeds the complete-card character limit")
    words = set(re.findall(r"[A-Za-z0-9]+", text))
    words.update(word.lower() for word in tuple(words))
    for run in re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+", text):
        for size in range(2, 7):
            words.update(
                run[start : start + size] for start in range(len(run) - size + 1)
            )
            if len(words) > _MAX_KEYWORDS:
                raise _Error(
                    "Teaching keywords exceed 4096 entries; no truncation allowed"
                )
    result = sorted(words)
    _keyword_values(result)
    if not result:
        raise _Error("Teaching text produced no usable keyword terms")
    return result


def _uuid(value):
    return str(uuid.UUID(value))


def _console(client, method, path, data=None):
    try:
        return client.api(method, path, data)
    except Exception as error:  # noqa: BLE001 - Console's safe exception type belongs to the caller.
        status = getattr(error, "status", None)
        suffix = f"HTTP {status}" if type(status) is int else "request failed"
        raise _Error(
            "Knowledge console " + method + ": " + suffix + "; details suppressed"
        ) from None


def _context(client, tenant):
    tenant = _uuid(tenant)
    url = urllib.parse.urlsplit(client.base)
    if (
        url.username
        or url.password
        or url.query
        or url.fragment
        or url.path.rstrip("/")
        or not url.hostname
        or not (
            url.scheme == "https"
            or (
                url.scheme == "http"
                and url.hostname in {"127.0.0.1", "::1", "localhost"}
            )
        )
    ):
        raise _Error("Knowledge API requires an HTTPS origin or loopback HTTP")
    current = _console(client, "GET", "/workspaces/current/summary")
    if current.get("id") != tenant or current.get("role") not in {
        "owner",
        "admin",
        "editor",
    }:
        raise _Error("Knowledge workspace or editing role differs from expected tenant")
    return tenant


def _methods(methods):
    if type(methods) is not list or not methods or len(methods) > 1024:
        raise _Error(
            "Knowledge import requires 1..1024 real approved methods; no empty or fixture records"
        )
    result = {}
    required = {
        "skill_id",
        "teacher_id",
        "subject",
        "topic_id",
        "name",
        "status",
        "version",
        "license",
        "applicable",
        "not_applicable",
        "steps",
        "examples",
        "counterexamples",
        "sources",
        "audit",
        "content_hash",
    }
    for method in methods:
        if (
            type(method) is not dict
            or set(method) != required
            or method.get("status") != "approved"
        ):
            raise _Error(
                "Knowledge import accepts only full, validated approved method cards"
            )
        text = _canonical(method)
        if (
            len(text) > _MAX_CHARS
            or _SEPARATOR in text
            or re.search(r"!\[.*?\]\(", text)
        ):
            raise _Error(
                "Method exceeds native single-segment limit or contains an active image reference"
            )
        for field in ("skill_id", "teacher_id", "topic_id"):
            if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,127}", method[field]):
                raise _Error("Invalid knowledge method identifier")
        if re.search(
            r"fixture|synthetic|never-import|example\.com", text, re.IGNORECASE
        ):
            raise _Error(
                "Engineering fixtures must never enter the production knowledge import"
            )
        if (
            not method["sources"]
            or not method["steps"]
            or not method["applicable"]
            or not method["examples"]
        ):
            raise _Error(
                "Knowledge method lacks evidence, steps, applicability, or recall example"
            )
        if not all(
            method["audit"][gate].get("passed") is True
            for gate in ("permission", "attribution", "method")
        ):
            raise _Error("Knowledge method has not passed every audit gate")
        for source in method["sources"]:
            if (
                not re.fullmatch(r"[0-9a-f]{40}", source["commit"])
                or source["commit"] == "0" * 40
                or not source["quote"].strip()
                or not source["locator"].strip()
                or source["evidence_type"]
                not in {"primary", "community_notes", "community_transcript"}
            ):
                raise _Error(
                    "Knowledge method requires pinned, located source evidence"
                )
        actual = _digest(
            {key: value for key, value in method.items() if key != "content_hash"}
        )
        if actual != method["content_hash"] or method["skill_id"] in result:
            raise _Error("Knowledge method hash mismatch or duplicate skill ID")
        # Native hit testing limits queries to 250 characters; never truncate a test.
        for query in (method["name"], method["examples"][0]["input"]):
            if type(query) is not str or not query.strip() or len(query) > 250:
                raise _Error(
                    "Method name and first recall example must contain 1..250 characters"
                )
        result[method["skill_id"]] = copy.deepcopy(method)
    return dict(sorted(result.items()))


def _read_key(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid not in {0, os.geteuid()}
            or stat.S_IMODE(info.st_mode) != 0o600
        ):
            raise _Error(
                "Knowledge key file must be a regular private file with mode 0600"
            )
        value = stream.read(1025)
    if len(value) > 1024:
        raise _Error("Knowledge key file exceeds the credential size limit")
    return value.decode().strip()


def _key_parent(path):
    parent = Path(path).parent
    info = parent.stat()
    if (
        parent.is_symlink()
        or not stat.S_ISDIR(info.st_mode)
        or info.st_uid != os.geteuid()
        or stat.S_IMODE(info.st_mode) != 0o700
    ):
        raise _Error(
            "New knowledge key requires a caller-owned runtime directory with mode 0700"
        )


def _write_key(path, token):
    _key_parent(path)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write(token + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    fd = os.open(Path(path).parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _token(client, tenant, token, token_file, *, knowledge=None, save=None):
    if token is not None and token_file is not None:
        raise _Error("Supply a knowledge token or token_file, not both")
    if token_file is not None:
        try:
            token = _read_key(token_file)
        except FileNotFoundError:
            if save is None:
                raise _Error(
                    "Knowledge key file is missing; verification cannot provision keys"
                ) from None
            _key_parent(token_file)
    if token is None and token_file is None:
        cached = getattr(client, "_kaogong_knowledge_token", None)
        if cached and cached[:2] == (client.base, tenant):
            token = cached[2]
    keys = _console(client, "GET", "/datasets/api-keys")["data"]
    if token is None:
        if save is None:
            raise _Error("Knowledge verification requires its dedicated API key")
        if knowledge.get("key_intent"):
            raise _Error(
                "Knowledge key was already attempted; restore its protected key file, never blindly create another"
            )
        if len(keys) >= 10:
            raise _Error(
                "Native knowledge API key limit reached; no existing keys were changed"
            )
        knowledge["key_intent"] = {
            "marker": str(uuid.uuid4()),
            "phase": "creating",
            "previous_ids": [_uuid(k["id"]) for k in keys],
        }
        save()
        # Reveal-once response. List responses are masked and cannot recover it.
        created = _console(
            client,
            "POST",
            "/datasets/api-keys",
            {"dataset_ids": [], "knowledge_space_ids": []},
        )
        token = created["token"]
        _valid_token(token)
        if (
            created.get("type") != "dataset"
            or created.get("dataset_ids")
            or created.get("knowledge_space_ids")
        ):
            raise _Error("Unexpected knowledge API key grant; no credentials accepted")
        if token_file is not None:
            _write_key(token_file, token)
        knowledge["key_intent"].update(id=_uuid(created["id"]), phase="created")
        save()
        keys = _console(client, "GET", "/datasets/api-keys")["data"]
    _valid_token(token)
    masked = token[:5] + "..." + token[-4:]
    matches = [
        key
        for key in keys
        if key.get("type") == "dataset" and key.get("token") == masked
    ]
    if (
        len(matches) != 1
        or matches[0].get("dataset_ids")
        or matches[0].get("knowledge_space_ids")
    ):
        raise _Error(
            "Knowledge API key is not uniquely bound to the expected workspace-wide dataset grant"
        )
    if knowledge is not None and knowledge.get("key_intent"):
        intent = knowledge["key_intent"]
        if intent.get("id") and intent["id"] != matches[0]["id"]:
            raise _Error(
                "Knowledge key identity changed; restore the managed runtime credential"
            )
        if intent.get("phase") != "created":
            if matches[0]["id"] in intent["previous_ids"]:
                raise _Error(
                    "Cannot reconcile knowledge key creation with a pre-existing key"
                )
            intent.update(id=_uuid(matches[0]["id"]), phase="created")
            save()
    client._kaogong_knowledge_token = (client.base, tenant, token)
    return token


def _valid_token(token):
    if type(token) is not str or not re.fullmatch(
        r"dataset-[A-Za-z0-9_-]{8,512}", token
    ):
        raise _Error(
            "Expected an unmasked native dataset API key, not a console or app credential"
        )


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise _Error("Knowledge API redirect refused")


class _Api:
    def __init__(self, base, token):
        self.base = base.rstrip("/")
        self.token = token
        # Never reuse Console.opener: neither cookie jar nor CSRF belongs here.
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), _NoRedirect()
        )

    def __call__(self, method, path, data=None, *, deadline=None):
        if not path.startswith("/datasets") or path.startswith("//"):
            raise _Error("Invalid knowledge API path")
        request = urllib.request.Request(
            self.base + "/v1" + path,
            method=method,
            data=None if data is None else _canonical(data).encode(),
            headers={
                "Authorization": "Bearer " + self.token,
                "Content-Type": "application/json",
            },
        )
        for attempt in range(3 if method == "GET" else 1):
            remaining = 30 if deadline is None else min(30, deadline - time.monotonic())
            if remaining <= 0:
                raise _Error(
                    "Knowledge indexing deadline exceeded; old mappings remain usable"
                )
            try:
                with self.opener.open(request, timeout=remaining) as response:
                    payload = response.read(_MAX_RESPONSE + 1)
                if len(payload) > _MAX_RESPONSE:
                    raise _Error("Knowledge API response exceeds size limit")
                return json.loads(payload) if payload else {}
            except urllib.error.HTTPError as error:
                status = error.code
                error.close()
                if (
                    method == "GET"
                    and attempt < 2
                    and (status == 429 or status >= 500)
                    and (deadline is None or time.monotonic() + 2**attempt < deadline)
                ):
                    time.sleep(2**attempt)
                    continue
                raise _Error(
                    f"Knowledge {method}: HTTP {status}; response suppressed, reconcile writes before retry"
                ) from None
            except (urllib.error.URLError, TimeoutError, ConnectionError, OSError):
                raise _Error(
                    "Knowledge transport failure; reconcile create intent before retrying"
                ) from None
            except (UnicodeError, ValueError):
                raise _Error(
                    "Malformed knowledge API response; content suppressed"
                ) from None


def _list(api, path, *, deadline=None):
    result = []
    for page in range(1, 101):
        response = api("GET", f"{path}?page={page}&limit=100", deadline=deadline)
        items = response["data"]
        if type(items) is not list or type(response["has_more"]) is not bool:
            raise _Error("Malformed knowledge listing")
        result.extend(items)
        if not response["has_more"]:
            ids = [_uuid(item["id"]) for item in result]
            if len(set(ids)) != len(ids):
                raise _Error("Knowledge pagination repeated resource IDs")
            return result
    raise _Error("Knowledge inventory exceeds the pagination safety limit")


def _dataset(client, api, mapping):
    path = "/datasets/" + _uuid(mapping["dataset_id"])
    detail = api("GET", path)
    console = _console(client, "GET", path)
    for resource in (detail, console):
        if (
            resource["id"] != mapping["dataset_id"]
            or resource["description"] != mapping["marker"]
            or resource["name"] != mapping["name"]
            or resource["permission"] != "only_me"
            or resource["provider"] != "vendor"
            or resource["indexing_technique"] != mapping["indexing_technique"]
            or resource.get("pipeline_id")
            or resource.get("is_multimodal")
            or resource.get("enable_api") is not True
            or resource.get("built_in_field_enabled")
            or resource.get("summary_index_setting", {}).get("enable")
        ):
            raise _Error(
                "Managed knowledge identity, permissions, or indexing mode changed"
            )
        actual = resource["retrieval_model_dict"]
        if any(
            actual.get(key) != value
            for key, value in mapping["retrieval_model"].items()
        ):
            raise _Error(
                "Managed knowledge retrieval settings changed; refusing overwrite"
            )
        if mapping["indexing_technique"] == "high_quality" and any(
            resource.get(key) != mapping["embedding"][key]
            for key in ("embedding_model", "embedding_model_provider")
        ):
            raise _Error("Managed knowledge embedding model changed")
    if (
        mapping["indexing_technique"] == "high_quality"
        and detail.get("embedding_available") is not True
    ):
        raise _Error(
            "Managed knowledge embedding model is unavailable; no silent economy fallback"
        )
    return path


def _metadata(api, path, mapping, save):
    fields = api("GET", path + "/metadata")["doc_metadata"]
    by_name = {field["name"]: field for field in fields}
    if len(by_name) != len(fields) or set(by_name) - set(_FIELDS):
        raise _Error(
            "Unexpected metadata fields in managed knowledge; no fields were overwritten"
        )
    for name in _FIELDS:
        intent = mapping["metadata"].get(name)
        field = by_name.get(name)
        if intent is None:
            if field is not None:
                raise _Error("Unmanaged metadata field found; refusing to adopt it")
            intent = {"marker": str(uuid.uuid4()), "phase": "creating"}
            mapping["metadata"][name] = intent
            save()
            field = api("POST", path + "/metadata", {"type": "string", "name": name})
        elif field is None:
            raise _Error(
                "Uncertain metadata creation or removed field; no create was retried"
            )
        if (
            field["name"] != name
            or field["type"] != "string"
            or (intent.get("id") and intent["id"] != field["id"])
        ):
            raise _Error("Managed metadata identity or type changed")
        if intent.get("phase") != "created":
            intent.update(id=_uuid(field["id"]), phase="created")
            save()


def _document(api, path, entry, method, metadata, *, deadline=None):
    doc_path = path + "/documents/" + _uuid(entry["document_id"])
    detail = api("GET", doc_path, deadline=deadline)
    if detail["id"] != entry["document_id"] or detail["name"] != entry["name"]:
        raise _Error("Managed knowledge document identity changed")
    if detail.get("enabled") is not True or detail.get("archived") is not False:
        raise _Error("Managed knowledge document was disabled or archived")
    status = detail["indexing_status"]
    if status in {"error", "paused", "stopped"} or detail.get("error"):
        raise _Error("Knowledge indexing failed; old mappings were not switched")
    if status != "completed":
        if status not in {"waiting", "parsing", "cleaning", "splitting", "indexing"}:
            raise _Error("Unrecognized knowledge indexing status")
        return None
    segments = _list(api, doc_path + "/segments", deadline=deadline)
    if len(segments) != 1:
        raise _Error(
            "Knowledge method must be exactly one full segment; no split or empty result accepted"
        )
    segment = segments[0]
    if (
        segment["document_id"] != entry["document_id"]
        or segment["content"] != _canonical(method)
        or segment.get("enabled") is not True
        or segment.get("error")
        or (entry.get("segment_id") and entry["segment_id"] != segment["id"])
    ):
        raise _Error("Knowledge segment content, identity, or indexing status changed")
    if segment["status"] != "completed":
        if deadline is not None and segment["status"] in {
            "waiting",
            "indexing",
            "re_segment",
        }:
            return None
        raise _Error("Knowledge segment indexing is not completed")
    if metadata is not None:
        fields = detail.get("doc_metadata") or []
        values = {field["name"]: field for field in fields}
        if len(values) != len(fields) or set(values) != set(_FIELDS):
            raise _Error(
                "Document metadata does not match the explicit managed field mapping"
            )
        for name in _FIELDS:
            if (
                values[name]["id"] != metadata[name]
                or values[name]["type"] != "string"
                or values[name]["value"] != method[name]
            ):
                raise _Error("Knowledge document metadata value or ID mismatch")
    return detail, segment


def _enrich_keywords(api, path, entry, method, metadata, terms, save, timeout, mutable):
    deadline = time.monotonic() + timeout
    ready = _document(api, path, entry, method, metadata, deadline=deadline)
    if ready is None:
        raise _Error("Keyword enrichment requires a completed full method segment")
    original = _keyword_values(ready[1].get("keywords"))
    intent = entry.get("keyword_intent")
    if intent is None:
        if not mutable:
            raise _Error(
                "Accepted knowledge generation has no keyword intent; refusing in-place strategy change"
            )
        desired = sorted(set(original) | set(terms))
        _keyword_values(desired)
        intent = {
            "marker": str(uuid.uuid4()),
            "strategy": _KEYWORD_STRATEGY,
            "content_hash": method["content_hash"],
            "before": copy.deepcopy(original),
            "desired": desired,
            "phase": "updating",
        }
        entry["keyword_intent"] = intent
        save()
    desired = sorted(set(_keyword_values(intent["before"])) | set(terms))
    _keyword_values(desired)
    if (
        intent["strategy"] != _KEYWORD_STRATEGY
        or intent["content_hash"] != method["content_hash"]
        or intent["desired"] != desired
        or intent["phase"] not in {"updating", "indexed"}
    ):
        raise _Error("Persisted teaching keyword strategy or intent changed")
    # Read again after persisting intent. Native update has no compare-and-swap;
    # omit content/answer/enabled so a concurrent text edit is never overwritten.
    sent = False
    while True:
        ready = _document(api, path, entry, method, metadata, deadline=deadline)
        if ready is not None:
            actual = _keyword_values(ready[1].get("keywords"))
            if sorted(actual) == desired:
                if intent["phase"] != "indexed":
                    intent["phase"] = "indexed"
                    save()
                return
            if sorted(actual) != sorted(intent["before"]):
                raise _Error(
                    "Managed segment keywords changed outside the pending intent; refusing overwrite"
                )
            if intent["phase"] == "indexed" or not mutable:
                raise _Error("Accepted segment keywords changed; refusing overwrite")
            if not sent:
                api(
                    "POST",
                    path
                    + "/documents/"
                    + _uuid(entry["document_id"])
                    + "/segments/"
                    + _uuid(entry["segment_id"]),
                    {"segment": {"keywords": desired}},
                    deadline=deadline,
                )
                sent = True
                continue
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise _Error("Keyword indexing timed out; no graph may be switched")
        time.sleep(min(2, remaining))


@_safe
def ensure_knowledge(
    client,
    tenant: str,
    methods: list[dict],
    state: dict,
    save_state,
    *,
    token: str | None = None,
    token_file=None,
    embedding: dict | None = None,
    index_timeout: int = 300,
) -> dict:
    """Import approved cards and return a verified, secret-free resource mapping.

    embedding is None for tested economy, or exactly
    {'provider': native_provider_id, 'model': model_name, 'verified': True}.
    Passing a missing token_file allows one native key creation and mode0600
    persistence; its parent must already exist with mode0700. Without a file,
    the newly created token survives only on this client instance.
    """
    methods = _methods(methods)
    if type(index_timeout) is not int or not 1 <= index_timeout <= 1800:
        raise _Error("Knowledge indexing timeout must be 1..1800 seconds")
    tenant = _context(client, tenant)
    if state.get("tenant_id") != tenant or state.get("origin") != client.base:
        raise _Error("Shared knowledge state belongs to a different tenant or origin")
    if embedding is not None and (
        type(embedding) is not dict
        or set(embedding) != {"provider", "model", "verified"}
        or embedding["verified"] is not True
        or any(
            type(embedding[k]) is not str or not embedding[k].strip()
            for k in ("provider", "model")
        )
    ):
        raise _Error(
            "High-quality knowledge requires an explicitly verified embedding provider and model"
        )
    technique = "high_quality" if embedding else "economy"
    teaching_terms = (
        {skill: _teaching_keywords(method) for skill, method in methods.items()}
        if embedding is None
        else {}
    )
    model = {
        "search_method": "semantic_search" if embedding else "keyword_search",
        "reranking_enable": False,
        "top_k": len(methods),
        "score_threshold_enabled": False,
    }
    embedding_fields = (
        {}
        if embedding is None
        else {
            "embedding_model": embedding["model"],
            "embedding_model_provider": embedding["provider"],
        }
    )
    catalog_hash = _digest(list(methods.values()))
    fingerprint = _digest(
        {
            "catalog": catalog_hash,
            "indexing_technique": technique,
            "embedding": embedding_fields,
        }
    )
    if "knowledge" not in state:
        state["knowledge"] = {
            "schema_version": 1,
            "tenant_id": tenant,
            "origin": client.base,
            "generations": {},
            "history": [],
            "current": None,
        }
        save_state(state)
    knowledge = state["knowledge"]
    if (
        knowledge["schema_version"] != 1
        or knowledge["tenant_id"] != tenant
        or knowledge["origin"] != client.base
    ):
        raise _Error("Knowledge state schema, tenant, or origin mismatch")

    def save():
        save_state(state)

    credential = _token(
        client, tenant, token, token_file, knowledge=knowledge, save=save
    )
    api = _Api(client.base, credential)
    generations = knowledge["generations"]
    if fingerprint not in generations:
        marker = "dify-kaogong-knowledge:" + str(uuid.uuid4())
        mapping = {
            "tenant_id": tenant,
            "origin": client.base,
            "marker": marker,
            "name": "kaogong-" + str(uuid.uuid4())[:32],
            "catalog_sha256": catalog_hash,
            "indexing_technique": technique,
            "embedding": embedding_fields,
            "retrieval_model": model,
            "metadata": {},
            "documents": {},
            "phase": "creating",
        }
        generations[fingerprint] = mapping
        save()
        result = api(
            "POST",
            "/datasets",
            {
                "name": mapping["name"],
                "description": marker,
                "permission": "only_me",
                "provider": "vendor",
                "indexing_technique": technique,
                "retrieval_model": model,
                "summary_index_setting": {"enable": False},
                **embedding_fields,
            },
        )
        mapping["dataset_id"] = _uuid(result["id"])
        mapping["phase"] = "created"
        save()
    else:
        mapping = generations[fingerprint]
    if (
        mapping["catalog_sha256"] != catalog_hash
        or mapping["indexing_technique"] != technique
        or mapping["embedding"] != embedding_fields
        or mapping["retrieval_model"] != model
        or mapping["tenant_id"] != tenant
        or mapping["origin"] != client.base
        or set(mapping["documents"]) - set(methods)
    ):
        raise _Error(
            "Knowledge generation intent differs from the requested approved catalog"
        )
    if not mapping.get("dataset_id"):
        matches = [
            item
            for item in _list(api, "/datasets")
            if item.get("description") == mapping["marker"]
        ]
        if len(matches) != 1:
            raise _Error(
                "Uncertain knowledge creation: no unique UUID marker found; no POST was retried"
            )
        mapping.update(dataset_id=_uuid(matches[0]["id"]), phase="created")
        save()
    path = _dataset(client, api, mapping)
    if technique == "economy" and mapping.get("keyword_strategy") not in {
        None,
        _KEYWORD_STRATEGY,
    }:
        raise _Error("Managed knowledge uses a different immutable keyword strategy")
    _metadata(api, path, mapping, save)
    metadata = {name: mapping["metadata"][name]["id"] for name in _FIELDS}
    existing = _list(api, path + "/documents")
    expected_names = {entry["name"]: entry for entry in mapping["documents"].values()}
    if (
        len({item["name"] for item in existing}) != len(existing)
        or any(item["name"] not in expected_names for item in existing)
        or any(
            expected_names[item["name"]].get("document_id") not in {None, item["id"]}
            for item in existing
            if item["name"] in expected_names
        )
    ):
        raise _Error(
            "Unmanaged documents found in dedicated knowledge generation; refusing changes"
        )
    for skill_id, method in methods.items():
        entry = mapping["documents"].get(skill_id)
        if entry is None:
            entry = {
                "name": "kaogong-method:" + str(uuid.uuid4()),
                "phase": "creating",
                **{name: method[name] for name in _FIELDS},
            }
            mapping["documents"][skill_id] = entry
            save()
            result = api(
                "POST",
                path + "/document/create-by-text",
                {
                    "name": entry["name"],
                    "text": _canonical(method),
                    "doc_form": "text_model",
                    "doc_language": "Chinese",
                    "indexing_technique": technique,
                    "retrieval_model": model,
                    **embedding_fields,
                    "process_rule": {
                        "mode": "custom",
                        "rules": {
                            "pre_processing_rules": [],
                            "segmentation": {
                                "separator": _SEPARATOR,
                                "max_tokens": _MAX_CHARS,
                                "chunk_overlap": 0,
                            },
                        },
                    },
                },
            )
            entry.update(
                document_id=_uuid(result["document"]["id"]),
                batch=result["batch"],
                phase="indexing",
            )
            save()
        if not entry.get("document_id"):
            matches = [item for item in existing if item["name"] == entry["name"]]
            if len(matches) != 1:
                raise _Error(
                    "Uncertain document creation: no unique UUID marker found; no POST was retried"
                )
            entry.update(document_id=_uuid(matches[0]["id"]), phase="indexing")
            save()
        if any(entry[name] != method[name] for name in _FIELDS):
            raise _Error("Persisted document intent differs from approved method")
        deadline = time.monotonic() + index_timeout
        while True:
            ready = _document(api, path, entry, method, None, deadline=deadline)
            if ready is not None:
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise _Error(
                    "Knowledge indexing timed out; old mappings remain unchanged"
                )
            time.sleep(min(2, remaining))
        detail, segment = ready
        entry["segment_id"] = _uuid(segment["id"])
        current_metadata = {
            field["name"]: field for field in detail.get("doc_metadata") or []
        }
        if entry["phase"] != "ready":
            if any(
                name not in _FIELDS
                or field["value"] != method[name]
                or field["id"] != metadata[name]
                for name, field in current_metadata.items()
            ):
                raise _Error(
                    "Unexpected document metadata before mapping; refusing overwrite"
                )
            if set(current_metadata) != set(_FIELDS):
                entry["phase"] = "mapping"
                save()
                api(
                    "POST",
                    path + "/documents/metadata",
                    {
                        "operation_data": [
                            {
                                "document_id": entry["document_id"],
                                "partial_update": True,
                                "metadata_list": [
                                    {
                                        "id": metadata[name],
                                        "name": name,
                                        "value": method[name],
                                    }
                                    for name in _FIELDS
                                ],
                            }
                        ]
                    },
                )
            entry["phase"] = "ready"
            save()
        _document(api, path, entry, method, metadata)
        if technique == "economy":
            mutable = mapping["phase"] == "created" and (
                knowledge["current"] is None
                or knowledge["current"]["dataset_id"] != mapping["dataset_id"]
            )
            _enrich_keywords(
                api,
                path,
                entry,
                method,
                metadata,
                teaching_terms[skill_id],
                save,
                index_timeout,
                mutable,
            )
    result = {
        key: copy.deepcopy(value)
        for key, value in mapping.items()
        if key not in {"metadata", "phase"}
    }
    result.update(
        metadata=metadata,
        dataset_ids=[mapping["dataset_id"]],
        retrieval_top_k=len(methods),
    )
    if technique == "economy":
        result["keyword_strategy"] = _KEYWORD_STRATEGY
    result["verification"] = verify_retrieval(
        client, tenant, result, list(methods.values()), token=credential
    )
    if technique == "economy":
        mapping["keyword_strategy"] = _KEYWORD_STRATEGY
    if knowledge["current"] != result:
        if knowledge["current"] is not None:
            knowledge["history"].append(copy.deepcopy(knowledge["current"]))
        knowledge["current"] = copy.deepcopy(result)
    mapping["phase"] = "ready"
    save()
    return result


@_safe
def verify_retrieval(
    client,
    tenant: str,
    knowledge: dict,
    methods: list[dict],
    *,
    token: str | None = None,
    token_file=None,
) -> dict:
    """Check actual full-card recall plus native teacher/status denial probes.

    Uses the returned ensure_knowledge mapping, not the outer shared state.
    Does not provision keys, create documents, or modify metadata. Native
    /retrieve itself records query audits. Node execution is tested separately.
    """
    methods = _methods(methods)
    tenant = _context(client, tenant)
    if (
        knowledge["tenant_id"] != tenant
        or knowledge["origin"] != client.base
        or knowledge["catalog_sha256"] != _digest(list(methods.values()))
    ):
        raise _Error(
            "Retrieval mapping is not for this tenant, origin, and approved catalog"
        )
    if set(knowledge["documents"]) != set(methods) or set(knowledge["metadata"]) != set(
        _FIELDS
    ):
        raise _Error(
            "Retrieval mapping does not cover exactly the approved methods and required metadata"
        )
    credential = _token(client, tenant, token, token_file)
    api = _Api(client.base, credential)
    path = _dataset(client, api, knowledge)
    fields = api("GET", path + "/metadata")["doc_metadata"]
    if (
        len(fields) != len(_FIELDS)
        or {field["name"]: field["id"] for field in fields if field["type"] == "string"}
        != knowledge["metadata"]
    ):
        raise _Error("Native metadata fields differ from managed retrieval mapping")
    documents = _list(api, path + "/documents")
    if {item["id"] for item in documents} != {
        entry["document_id"] for entry in knowledge["documents"].values()
    }:
        raise _Error(
            "Dedicated knowledge generation contains missing or unrelated documents"
        )
    if knowledge["retrieval_model"]["top_k"] < len(documents):
        raise _Error(
            "Retrieval Top-K could starve teachers in the native economy index"
        )
    for skill_id, method in methods.items():
        entry = knowledge["documents"][skill_id]
        ready = _document(api, path, entry, method, knowledge["metadata"])
        if ready is None:
            raise _Error(
                "Knowledge document is not indexed; retrieval cannot be accepted"
            )
        if knowledge["indexing_technique"] == "economy":
            intent = entry.get("keyword_intent", {})
            desired = sorted(
                set(_keyword_values(intent.get("before")))
                | set(_teaching_keywords(method))
            )
            _keyword_values(desired)
            if (
                knowledge.get("keyword_strategy") != _KEYWORD_STRATEGY
                or intent.get("strategy") != _KEYWORD_STRATEGY
                or intent.get("phase") != "indexed"
                or intent.get("content_hash") != method["content_hash"]
                or intent.get("desired") != desired
                or sorted(_keyword_values(ready[1].get("keywords"))) != desired
            ):
                raise _Error(
                    "Verified teaching keyword strategy or native keyword readback differs"
                )
    checked = []
    for skill_id, method in methods.items():
        queries = list(dict.fromkeys([method["name"], method["examples"][0]["input"]]))
        conditions = [("teacher_id", method["teacher_id"]), ("status", "approved")]
        for query in queries:
            for probe in ("positive", "wrong_teacher", "wrong_status"):
                values = dict(conditions)
                if probe == "wrong_teacher":
                    values["teacher_id"] = "not-a-teacher-" + str(uuid.uuid4())
                elif probe == "wrong_status":
                    values["status"] = "quarantined"
                retrieval = {
                    **knowledge["retrieval_model"],
                    "metadata_filtering_conditions": {
                        "logical_operator": "and",
                        "conditions": [
                            {"name": name, "comparison_operator": "is", "value": value}
                            for name, value in values.items()
                        ],
                    },
                }
                response = api(
                    "POST",
                    path + "/retrieve",
                    {"query": query, "retrieval_model": retrieval},
                )
                records = response["records"]
                if (
                    type(records) is not list
                    or response.get("query", {}).get("content") != query
                ):
                    raise _Error("Malformed native retrieval response")
                if probe != "positive":
                    if records:
                        raise _Error(
                            "Native teacher/status hard filtering failed; no graph may be switched"
                        )
                    continue
                if not records:
                    raise _Error(
                        "Actual approved-method recall returned no evidence for "
                        + skill_id
                        + (
                            " (method name)"
                            if query == method["name"]
                            else " (example)"
                        )
                        + "; economy fallback is not accepted"
                    )
                found = set()
                for record in records:
                    segment = record["segment"]
                    doc = segment["document"]
                    metadata = doc["doc_metadata"]
                    retrieved = methods.get(metadata.get("skill_id"))
                    if (
                        retrieved is None
                        or any(
                            metadata.get(name) != retrieved[name] for name in _FIELDS
                        )
                        or metadata["teacher_id"] != method["teacher_id"]
                    ):
                        raise _Error(
                            "Native retrieval mixed teachers, unapproved methods, or wrong content hashes"
                        )
                    entry = knowledge["documents"][retrieved["skill_id"]]
                    if (
                        segment["id"] != entry["segment_id"]
                        or segment["document_id"] != entry["document_id"]
                        or doc["id"] != entry["document_id"]
                        or segment["content"] != _canonical(retrieved)
                        or segment.get("enabled") is not True
                        or segment["status"] != "completed"
                    ):
                        raise _Error(
                            "Retrieved evidence differs from the verified full method segment"
                        )
                    found.add(retrieved["skill_id"])
                if skill_id not in found:
                    raise _Error(
                        "Representative query failed to recall its approved method"
                    )
        checked.append(
            {
                "skill_id": skill_id,
                "positive_queries": len(queries),
                "teacher_filter": True,
                "status_filter": True,
            }
        )
    return {
        "passed": True,
        "indexing_technique": knowledge["indexing_technique"],
        "methods": checked,
        "native_node_execution_tested": False,
    }
