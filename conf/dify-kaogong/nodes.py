"""Audited, stdlib-only Dify Code-node helpers; no I/O or model invocation.

Public contracts:
* validate_catalog(taxonomy, sources, methods) returns a detached catalog with
  taxonomy/sources/methods envelopes, approved_teacher_ids and approved_skill_ids.
  Invalid catalogs raise ValueError. All runtime boundaries revalidate it.
* enumerate_teachers(topics, catalog, *, limit=None, offset=0) returns topics,
  teachers, pending, completed_before, total, offset and limit. Each teacher is
  {teacher_id, name, skill_ids}. The caller's native Iteration, not this module,
  enforces concurrency <= 3. There is no global top-K or relevance-score cutoff.
* calculate(operation, operands, *, places=2, rounding='half_up') returns
  {operation, values: {field: decimal_string}, unit, places, rounding}.
* verify_solution(solution, teacher_id, topics, catalog, *, provided_skill_ids,
  provided_source_ids, question='') returns status, reason, teacher_id and, on
  accepted structure, trusted display data. It never proves semantic truth.
* render(enumeration, results, catalog, *, question='', limit_chars=16000)
  returns {answer: str, state: str}. Results are envelopes containing exactly
  teacher_id, solution, provided_skill_ids, provided_source_ids. They are raw
  node results, NOT pre-approved verifier output. Missing results are failures.
* main(query: str, state: str='') returns {answer: str, state: str}. This is ONLY
  the empty-catalog fallback, not a simulated native teacher retrieval graph.

Full method schema (all keys required; no model-supplied metadata is trusted):
  skill_id, teacher_id, subject, topic_id, name, status, version, license,
  applicable: [{condition_id, text}], not_applicable: [text], steps: [text],
  examples: [{input, output}], counterexamples: [{input, reason}],
  sources: [{source_id, repo, commit, path, url, license, evidence_type,
             locator, quote, summary}],
  audit: {permission: {passed: bool, basis: text},
          attribution: {passed: bool, basis: text},
          method: {passed: bool, basis: text}, reviewer, reviewed_on},
  content_hash: lowercase SHA256 of canonical UTF-8 JSON for the method with
                content_hash removed (sort_keys=True, separators=(',', ':'),
                ensure_ascii=False). method_content_hash implements this.

Answered solution schema (all keys required):
  {status:'answered', skill_id, evidence:[{source_id, locator, quote}],
   conditions:[{condition_id, material_quote}],
   steps:[{kind:'citation', evidence_index: int} |
          {kind:'material', quote: text} |
          {kind:'calculation', operation, operands, places, rounding}],
   answer:{kind:'calculation', step_index:int, field:text, value:text} |
          {kind:'evidence', evidence_index:int},
   uncertainties:[code]}
  skip/failed schema: {status:'skip'|'failed', reason: allowed_reason_code}.
  Quotes must equal whole audited quote records, not arbitrary substrings.
  Applicability material quotes must occur in the original question, but this
  is only provenance checking, not logical entailment. Growth operands must
  match explicit problem roles, rate and unit; general arithmetic operands must
  occur in the question or a preceding calculation. Their derivation is not a proof. Thus
  even numerical results remain marked as conditionally checked, not certified
  answers. Free-form claims, URLs, names and reasoning are never rendered.

Catalogs are trusted audit inputs supplied by the application, NEVER by a user
or an LLM. Structural checks cannot establish real-world permission, authorship
or correctness. Hashes detect accidental content drift, not malicious audits.
provided_skill_ids/provided_source_ids must likewise come from the application's
hard-filtered retrieval boundary, not fields a model may invent. If native
teacher_id/status metadata filtering is unavailable, stop with filter_unavailable.
"""

import copy
import hashlib
import json
import re
from datetime import date
from decimal import (
    ROUND_DOWN,
    ROUND_HALF_EVEN,
    ROUND_HALF_UP,
    Decimal,
    InvalidOperation,
    localcontext,
)
from urllib.parse import quote, unquote, urlsplit

NO_MATCH = "当前已审核资料库中未找到适用的老师方法"
MAX_TEACHERS = 128
MAX_METHODS = 1024
MAX_QUERY = 4000
MAX_STATE = 2048
MAX_TURNS = 8
STATUSES = {"pending", "approved", "quarantined"}
EVIDENCE_TYPES = {
    "primary",
    "community_transcript",
    "community_notes",
    "syllabus_only",
    "repository_tree",
    "repository_readme",
}
SUBJECTS = {"xingce", "shenlun", "interview", "unknown"}
UNITS = {
    "",
    "元",
    "万元",
    "亿元",
    "人",
    "万人",
    "吨",
    "万吨",
    "件",
    "个",
    "家",
    "户",
    "公里",
    "平方公里",
}
ROUNDINGS = {"half_up": ROUND_HALF_UP, "half_even": ROUND_HALF_EVEN, "down": ROUND_DOWN}
GROWTH_ROLES = {
    "current": r"(?:现期|本期)(?:营业收入|销售收入|销售额|收入|产值|产量|量|值)?",
    "base": r"基期(?:营业收入|销售收入|销售额|收入|产值|产量|量|值)?",
}
GROWTH_RATE = r"(?:(?:同比|环比)?增长率|(?:同比|环比)增长)"
REASONS = {
    "no_evidence": "未检索到本老师的已审核依据",
    "not_applicable": "适用条件不满足",
    "missing_material": "缺少题干或材料",
    "ocr_ambiguous": "图像或文字识别有歧义",
    "timeout": "该老师分支超时",
    "model_failure": "模型或结构化输出失败",
    "retrieval_failure": "检索、插件或索引失败",
    "filter_unavailable": "无法执行老师和审核状态硬过滤",
    "conflict": "存在尚未解决的依据或结论冲突",
    "invalid_output": "输出未通过结构、范围或证据校验",
    "not_returned": "该老师分支没有返回结果",
    "unverified_conditions": "题目条件与方法适用性仍需人工核验",
}


def _fail(message):
    raise ValueError(message)


def _object(value, required, optional=()):
    if (
        type(value) is not dict
        or set(value) - set(required) - set(optional)
        or set(required) - set(value)
    ):
        _fail("invalid object fields: " + ",".join(sorted(required)))
    return value


def _text(value, maximum=2000, empty=False):
    if (
        type(value) is not str
        or len(value) > maximum
        or (not empty and not value.strip())
    ):
        _fail("invalid text")
    if any(ord(char) < 32 and char not in "\n\t" for char in value):
        _fail("control character in text")
    return value


def _identifier(value):
    if type(value) is not str or not re.fullmatch(r"[a-z][a-z0-9_.-]{0,63}", value):
        _fail("invalid identifier")
    return value


def _list(value, maximum, minimum=0):
    if type(value) is not list or not minimum <= len(value) <= maximum:
        _fail("invalid array size or type")
    return value


def _integer(value, minimum, maximum):
    if type(value) is not int or not minimum <= value <= maximum:
        _fail("invalid integer")
    return value


def _ids(value, maximum=MAX_METHODS):
    result = [_identifier(item) for item in _list(value, maximum)]
    if len(result) != len(set(result)):
        _fail("duplicate identifier")
    return result


def _bounded_json(value, maximum):
    try:
        encoded = json.dumps(
            value, ensure_ascii=False, allow_nan=False, separators=(",", ":")
        )
    except (TypeError, ValueError, RecursionError):
        _fail("invalid JSON value")
    if len(encoded.encode("utf-8")) > maximum:
        _fail("JSON exceeds capacity; split explicitly")
    return encoded


def _source(source, method=False):
    fields = {"repo", "commit", "path", "url", "license", "evidence_type"}
    fields |= (
        {"source_id", "locator", "quote", "summary"} if method else {"review_scope"}
    )
    _object(source, fields)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", _text(source["repo"], 200)):
        _fail("invalid repository")
    if not re.fullmatch(r"[0-9a-f]{40}", _text(source["commit"], 40)):
        _fail("source must use a pinned commit")
    path = _text(source["path"], 500)
    if (
        path.startswith("/")
        or any(part in {"", ".", ".."} for part in path.split("/"))
        or "\\" in path
        or any(ord(char) < 32 for char in path)
    ):
        _fail("invalid source path")
    url = urlsplit(_text(source["url"], 2000))
    roots = ["blob"] if method else ["blob", "tree"]
    expected = {
        "/" + source["repo"] + "/" + root + "/" + source["commit"] + "/" + path
        for root in roots
    }
    if (
        url.scheme != "https"
        or url.netloc != "github.com"
        or url.query
        or url.fragment
        or unquote(url.path) not in expected
    ):
        _fail("source URL must identify the exact pinned GitHub file")
    _text(source["license"], 300)
    if (
        type(source["evidence_type"]) is not str
        or source["evidence_type"] not in EVIDENCE_TYPES
    ):
        _fail("unknown evidence type")
    if method:
        _identifier(source["source_id"])
        _text(source["locator"], 300)
        _text(source["quote"], 2000)
        _text(source["summary"], 2000)
    else:
        _text(source["review_scope"], 2000)


def method_content_hash(method):
    """Canonical content hash; callers must explicitly audit before approving."""
    if type(method) is not dict:
        _fail("method must be an object")
    value = {key: item for key, item in method.items() if key != "content_hash"}
    try:
        encoded = json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        )
    except (ValueError, TypeError, RecursionError):
        _fail("method is not canonical JSON")
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def validate_catalog(taxonomy, sources, methods):
    """Fail closed on malformed records, drift, ownership or any approval gate."""
    _bounded_json([taxonomy, sources, methods], 2000000)
    _object(taxonomy, {"schema_version", "topics"})
    _object(
        sources,
        {"schema_version", "candidates", "quarantined_methods"},
        {"checked_at", "audit"},
    )
    _object(methods, {"schema_version", "methods"})
    for envelope in (taxonomy, sources, methods):
        if (
            type(envelope["schema_version"]) is not int
            or envelope["schema_version"] != 1
        ):
            _fail("unsupported schema version")
    if "checked_at" in sources:
        checked_at = _text(sources["checked_at"], 10)
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", checked_at):
            _fail("invalid source check date")
        date.fromisoformat(checked_at)
    if "audit" in sources:
        # Descriptive research metadata never grants runtime approval.
        _object(
            sources["audit"],
            {
                "candidate_count",
                "approved_count",
                "scope",
                "limits",
                "evidence_types",
                "repository_checks",
                "retrieval_errors",
                "exclusions",
                "gaps",
            },
        )
        _integer(sources["audit"]["candidate_count"], 0, MAX_TEACHERS)
        _integer(sources["audit"]["approved_count"], 0, MAX_TEACHERS)
        _text(sources["audit"]["scope"], 4000)
        for text in _list(sources["audit"]["limits"], 64):
            _text(text, 4000)
        if type(sources["audit"]["evidence_types"]) is not dict:
            _fail("invalid evidence-type audit descriptions")
        for key, text in sources["audit"]["evidence_types"].items():
            if key not in EVIDENCE_TYPES:
                _fail("unknown audit evidence type")
            _text(text, 4000)
        for field in ("repository_checks", "retrieval_errors", "exclusions", "gaps"):
            for record in _list(sources["audit"][field], 128):
                if type(record) is not dict:
                    _fail("invalid descriptive audit record")
    topics = {}
    for topic in _list(taxonomy["topics"], 128, 1):
        _object(topic, {"topic_id", "subject", "name"})
        key = _identifier(topic["topic_id"])
        if (
            key in topics
            or type(topic["subject"]) is not str
            or topic["subject"] not in SUBJECTS
        ):
            _fail("duplicate topic or invalid subject")
        if (key == "unknown") != (topic["subject"] == "unknown"):
            _fail("invalid unknown topic")
        _text(topic["name"], 100)
        topics[key] = topic
    if "unknown" not in topics:
        _fail("taxonomy requires unknown")
    teachers = {}
    for candidate in _list(sources["candidates"], MAX_TEACHERS):
        _object(candidate, {"teacher_id", "name", "status", "reason", "sources"})
        teacher_id = _identifier(candidate["teacher_id"])
        if (
            teacher_id in teachers
            or type(candidate["status"]) is not str
            or candidate["status"] not in STATUSES
        ):
            _fail("duplicate teacher or invalid status")
        _text(candidate["name"], 80)
        _text(candidate["reason"], 2000)
        seen = set()
        for source in _list(candidate["sources"], 64):
            _source(source)
            if source["url"] in seen:
                _fail("duplicate candidate source")
            seen.add(source["url"])
        if candidate["status"] == "approved" and not seen:
            _fail("approved teacher requires audited sources")
        teachers[teacher_id] = candidate
    quarantined = set()
    quarantined_locations = set()
    for record in _list(sources["quarantined_methods"], MAX_METHODS):
        _object(
            record,
            {
                "quarantine_id",
                "teacher_id",
                "name",
                "status",
                "reason",
                "verification",
                "sources",
            },
        )
        key = _identifier(record["quarantine_id"])
        _identifier(record["teacher_id"])
        _text(record["name"], 200)
        _text(record["reason"], 2000)
        _text(record["verification"], 4000)
        if record["status"] != "quarantined":
            _fail("quarantine record must remain quarantined")
        for source in _list(record["sources"], 64, 1):
            _source(source)
            quarantined_locations.add(
                (source["repo"], source["commit"], source["path"])
            )
        if key in quarantined:
            _fail("duplicate quarantine record")
        quarantined.add(key)
    approved = []
    seen_skills = set()
    seen_source_ids = set()
    for method in _list(methods["methods"], MAX_METHODS):
        _object(
            method,
            {
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
            },
        )
        skill_id = _identifier(method["skill_id"])
        teacher_id = _identifier(method["teacher_id"])
        topic_id = _identifier(method["topic_id"])
        if (
            skill_id in seen_skills
            or teacher_id not in teachers
            or topic_id not in topics
            or topic_id == "unknown"
        ):
            _fail("duplicate skill or unknown teacher/topic")
        seen_skills.add(skill_id)
        if (
            method["subject"] != topics[topic_id]["subject"]
            or type(method["status"]) is not str
            or method["status"] not in STATUSES
        ):
            _fail("invalid method subject/status")
        for field in ("name", "version", "license"):
            _text(method[field], 200)
        condition_ids = []
        for condition in _list(method["applicable"], 16, 1):
            _object(condition, {"condition_id", "text"})
            condition_ids.append(_identifier(condition["condition_id"]))
            _text(condition["text"])
        if len(condition_ids) != len(set(condition_ids)):
            _fail("duplicate applicability condition")
        for field in ("not_applicable", "steps"):
            for text in _list(method[field], 16, 1):
                _text(text)
        for field, output in (("examples", "output"), ("counterexamples", "reason")):
            for example in _list(method[field], 16, 1):
                _object(example, {"input", output})
                _text(example["input"])
                _text(example[output])
        audit = _object(
            method["audit"],
            {"permission", "attribution", "method", "reviewer", "reviewed_on"},
        )
        _text(audit["reviewer"], 200)
        try:
            reviewed_on = _text(audit["reviewed_on"], 10)
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", reviewed_on):
                _fail("invalid review date")
            date.fromisoformat(reviewed_on)
        except ValueError:
            _fail("invalid review date")
        passed = True
        for gate in ("permission", "attribution", "method"):
            _object(audit[gate], {"passed", "basis"})
            if type(audit[gate]["passed"]) is not bool:
                _fail("audit gate must be boolean")
            _text(audit[gate]["basis"])
            passed = passed and audit[gate]["passed"]
        teacher = teachers[teacher_id]
        candidate_sources = {item["url"]: item for item in teacher["sources"]}
        for source in _list(method["sources"], 16, 1):
            _source(source, method=True)
            if source["source_id"] in seen_source_ids:
                _fail("source ID reused across methods/teachers")
            seen_source_ids.add(source["source_id"])
            candidate_source = candidate_sources.get(source["url"])
            if candidate_source is None or any(
                candidate_source[field] != source[field]
                for field in ("repo", "commit", "path", "license", "evidence_type")
            ):
                _fail("method source not bound to this teacher's audited source")
            if source["license"] != method["license"]:
                _fail("method/source license mismatch")
            if method["status"] == "approved":
                license_label = source["license"].lower()
                if source["evidence_type"] not in {
                    "primary",
                    "community_transcript",
                    "community_notes",
                } or any(
                    license_label.startswith(prefix)
                    for prefix in (
                        "unknown",
                        "none",
                        "noassertion",
                        "unlicensed",
                        "no license",
                        "pending",
                    )
                ):
                    _fail("source does not support approved method use")
                if (
                    source["repo"],
                    source["commit"],
                    source["path"],
                ) in quarantined_locations:
                    _fail("source file is quarantined; no relabeled corrected method")
        if method["content_hash"] != method_content_hash(method):
            _fail("method content hash mismatch")
        if skill_id in quarantined and method["status"] != "quarantined":
            _fail("quarantined method cannot be reactivated")
        if method["status"] == "approved":
            if teacher["status"] != "approved" or not passed or skill_id in quarantined:
                _fail("approved method failed teacher status or three audit gates")
            approved.append(skill_id)
    active_teachers = sorted(
        {
            item["teacher_id"]
            for item in methods["methods"]
            if item["skill_id"] in approved
        }
    )
    if "audit" in sources and (
        sources["audit"]["candidate_count"] != len(teachers)
        or sources["audit"]["approved_count"] != len(active_teachers)
    ):
        _fail("descriptive audit counts disagree with usable catalog")
    return copy.deepcopy(
        {
            "schema_version": 1,
            "taxonomy": taxonomy,
            "sources": sources,
            "methods": methods,
            "approved_teacher_ids": active_teachers,
            "approved_skill_ids": sorted(approved),
        }
    )


def _catalog(catalog):
    _object(
        catalog,
        {
            "schema_version",
            "taxonomy",
            "sources",
            "methods",
            "approved_teacher_ids",
            "approved_skill_ids",
        },
    )
    if type(catalog["schema_version"]) is not int or catalog["schema_version"] != 1:
        _fail("invalid normalized catalog version")
    checked = validate_catalog(
        catalog["taxonomy"], catalog["sources"], catalog["methods"]
    )
    if checked != catalog:
        _fail("catalog derived fields were changed")
    return checked


def _topics(topics, catalog):
    chosen = _ids(topics, 16)
    known = {item["topic_id"] for item in catalog["taxonomy"]["topics"]}
    if not chosen or set(chosen) - known or ("unknown" in chosen and len(chosen) != 1):
        _fail("invalid taxonomy selection; clarify unknown separately")
    return sorted(chosen)


def enumerate_teachers(topics, catalog, *, limit=None, offset=0):
    """Enumerate every approved exact-topic teacher; explicit batches only."""
    catalog = _catalog(catalog)
    topics = _topics(topics, catalog)
    _integer(offset, 0, MAX_TEACHERS)
    if limit is not None:
        _integer(limit, 1, MAX_TEACHERS)
    matched = {}
    for method in catalog["methods"]["methods"]:
        if (
            method["skill_id"] in catalog["approved_skill_ids"]
            and method["topic_id"] in topics
        ):
            matched.setdefault(method["teacher_id"], []).append(method["skill_id"])
    names = {
        item["teacher_id"]: item["name"] for item in catalog["sources"]["candidates"]
    }
    teachers = [
        {"teacher_id": key, "name": names[key], "skill_ids": sorted(matched[key])}
        for key in sorted(matched)
    ]
    if offset > len(teachers):
        _fail("offset exceeds matched teacher count")
    end = len(teachers) if limit is None else min(len(teachers), offset + limit)
    return {
        "topics": topics,
        "teachers": teachers[offset:end],
        "pending": teachers[end:],
        "completed_before": teachers[:offset],
        "total": len(teachers),
        "offset": offset,
        "limit": limit,
    }


def _number(value):
    if type(value) is not str or not re.fullmatch(
        r"-?(?:0|[1-9][0-9]{0,12})(?:\.[0-9]{1,12})?", value
    ):
        _fail("operand must be a bounded plain decimal string")
    number = Decimal(value)
    if abs(number) > Decimal(1000000000000):
        _fail("operand exceeds magnitude bound")
    return number


def _unit(unit):
    if type(unit) is not str or unit not in UNITS:
        _fail("unsupported unit; convert explicitly before calculation")
    return unit


def calculate(operation, operands, *, places=2, rounding="half_up"):
    """Bounded Decimal arithmetic, no expressions, eval, floats or unit guessing."""
    if type(operation) is not str or operation not in {
        "growth_from_current",
        "growth_from_base",
        "add",
        "subtract",
        "multiply",
        "divide",
    }:
        _fail("unsupported operation")
    _integer(places, 0, 6)
    if type(rounding) is not str or rounding not in ROUNDINGS:
        _fail("unsupported rounding")
    with localcontext() as context:
        context.prec = 60
        if operation.startswith("growth_from_"):
            role = "current" if operation == "growth_from_current" else "base"
            _object(operands, {role, "rate", "unit"})
            value = _number(operands[role])
            unit = _unit(operands["unit"])
            rate_text = operands["rate"]
            if type(rate_text) is not str or not rate_text.endswith("%"):
                _fail("growth rate requires an explicit percent suffix")
            rate = _number(rate_text[:-1]) / Decimal(100)
            if value < 0 or rate <= -1 or rate > 100:
                _fail(
                    "invalid growth domain (nonnegative amount, -100% < rate <= 10000%)"
                )
            base = value / (1 + rate) if role == "current" else value
            current = value if role == "current" else base * (1 + rate)
            values = {"current": current, "base": base, "growth": current - base}
        else:
            _object(operands, {"left", "right"})
            for side in ("left", "right"):
                _object(operands[side], {"value", "unit"})
            left = _number(operands["left"]["value"])
            right = _number(operands["right"]["value"])
            left_unit = _unit(operands["left"]["unit"])
            right_unit = _unit(operands["right"]["unit"])
            if operation in {"add", "subtract"}:
                if left_unit != right_unit:
                    _fail("addition/subtraction requires matching units")
                value = left + right if operation == "add" else left - right
                unit = left_unit
            elif operation == "multiply":
                if left_unit and right_unit:
                    _fail("unsupported compound units")
                value, unit = left * right, left_unit or right_unit
            else:
                if right == 0:
                    _fail("division by zero")
                if right_unit and right_unit != left_unit:
                    _fail("unsupported ratio units")
                value = left / right
                unit = "" if left_unit == right_unit else left_unit
            values = {"result": value}
        if any(
            not number.is_finite() or abs(number) > Decimal("1e18")
            for number in values.values()
        ):
            _fail("result exceeds magnitude bound")
        quantum = Decimal(1).scaleb(-places)
        try:
            rounded = {
                key: number.quantize(quantum, rounding=ROUNDINGS[rounding])
                for key, number in values.items()
            }
        except InvalidOperation:
            _fail("result cannot be rounded safely")
        formatted = {
            key: format(abs(number) if number == 0 else number, "." + str(places) + "f")
            for key, number in rounded.items()
        }
    return {
        "operation": operation,
        "values": formatted,
        "unit": unit,
        "places": places,
        "rounding": rounding,
    }


def _bind_calculation(operation, operands, question, previous_steps):
    """Reject invented operands and explicit current/base/percent/unit swaps."""
    number = r"-?(?:0|[1-9][0-9]{0,12})(?:\.[0-9]{1,12})?"
    if operation.startswith("growth_from_"):
        role = "current" if operation == "growth_from_current" else "base"
        label = GROWTH_ROLES[role]
        units = "|".join(
            re.escape(unit)
            for unit in sorted(UNITS - {""}, key=lambda item: (-len(item), item))
        )
        amounts = re.findall(
            label
            + r"\s*(?:为|是|[:：=])?\s*("
            + number
            + r")\s*("
            + units
            + r")?(?=\s|[,，、;；。？?！!]|$)",
            question,
        )
        rates = re.findall(
            GROWTH_RATE + r"\s*(?:为|是|了|[:：=])?\s*(" + number + r")\s*[%％]",
            question,
        )
        if len(amounts) != 1 or len(rates) != 1:
            _fail(
                "growth requires one explicit amount role and one explicit percentage in the question"
            )
        if (
            _number(amounts[0][0]) != _number(operands[role])
            or amounts[0][1] != operands["unit"]
            or _number(rates[0]) != _number(operands["rate"][:-1])
        ):
            _fail("growth operands disagree with original role, percentage or unit")
        return
    available = set()
    units = "|".join(
        re.escape(unit)
        for unit in sorted(UNITS - {""}, key=lambda item: (-len(item), item))
    )
    pattern = (
        r"(?<![0-9A-Za-z_.+-])(" + number + r")\s*(" + units + r")?(?![0-9A-Za-z_.%％])"
    )
    for match in re.finditer(pattern, question):
        available.add((_number(match[1]), match[2] or ""))
    for step in previous_steps:
        if step["kind"] == "calculation":
            result = step["result"]
            for value in result["values"].values():
                available.add((Decimal(value), result["unit"]))
    for operand in operands.values():
        if (_number(operand["value"]), operand["unit"]) not in available:
            _fail("arithmetic operand lacks an input or prior-calculation origin")


def verify_solution(
    solution,
    teacher_id,
    topics,
    catalog,
    *,
    provided_skill_ids,
    provided_source_ids,
    question="",
):
    """Return a rejection instead of forwarding invalid or free-form model text."""
    try:
        catalog = _catalog(catalog)
        topics = _topics(topics, catalog)
        _identifier(teacher_id)
        _text(question, MAX_QUERY, empty=True)
        _bounded_json(solution, 24000)
        skills = _ids(provided_skill_ids, 64)
        sources = _ids(provided_source_ids, 128)
        legal = {
            item["skill_id"]: item
            for item in catalog["methods"]["methods"]
            if item["skill_id"] in catalog["approved_skill_ids"]
            and item["teacher_id"] == teacher_id
            and item["topic_id"] in topics
        }
        if (
            teacher_id not in catalog["approved_teacher_ids"]
            or not legal
            or set(skills) - set(legal)
        ):
            _fail("teacher/skill retrieval scope mismatch")
        source_records = {
            item["source_id"]: item for key in skills for item in legal[key]["sources"]
        }
        if set(sources) - set(source_records):
            _fail("unknown or cross-teacher source ID")
        if (
            type(solution) is not dict
            or type(solution.get("status")) is not str
            or solution.get("status") not in {"answered", "skip", "failed"}
        ):
            _fail("invalid solution status")
        if solution["status"] != "answered":
            _object(solution, {"status", "reason"})
            if type(solution["reason"]) is not str or solution["reason"] not in REASONS:
                _fail("unknown failure reason")
            return {
                "status": solution["status"],
                "reason": solution["reason"],
                "teacher_id": teacher_id,
            }
        _object(
            solution,
            {
                "status",
                "skill_id",
                "evidence",
                "conditions",
                "steps",
                "answer",
                "uncertainties",
            },
        )
        skill_id = _identifier(solution["skill_id"])
        if skill_id not in skills:
            _fail("skill was not supplied to this teacher branch")
        method = legal[skill_id]
        method_sources = {item["source_id"]: item for item in method["sources"]}
        evidence = []
        evidence_seen = set()
        for citation in _list(solution["evidence"], 16, 1):
            _object(citation, {"source_id", "locator", "quote"})
            source_id = _identifier(citation["source_id"])
            source = method_sources.get(source_id)
            if source_id not in sources or source is None or source_id in evidence_seen:
                _fail("unknown, duplicate or cross-method citation")
            if (
                citation["locator"] != source["locator"]
                or citation["quote"] != source["quote"]
            ):
                _fail("fabricated or altered quote/location")
            evidence_seen.add(source_id)
            evidence.append(copy.deepcopy(source))
        conditions = []
        condition_ids = set()
        allowed_conditions = {
            item["condition_id"]: item["text"] for item in method["applicable"]
        }
        for condition in _list(solution["conditions"], 16, 1):
            _object(condition, {"condition_id", "material_quote"})
            condition_id = _identifier(condition["condition_id"])
            quote = _text(condition["material_quote"], 1000)
            if (
                condition_id not in allowed_conditions
                or condition_id in condition_ids
                or quote not in question
            ):
                _fail("condition lacks a unique original-material locator")
            condition_ids.add(condition_id)
            conditions.append(
                {"condition": allowed_conditions[condition_id], "material_quote": quote}
            )
        if condition_ids != set(allowed_conditions):
            _fail("method applicability conditions omitted")
        steps = []
        for step in _list(solution["steps"], 16, 1):
            if type(step) is not dict or type(step.get("kind")) is not str:
                _fail("invalid step")
            if step["kind"] == "citation":
                _object(step, {"kind", "evidence_index"})
                index = _integer(step["evidence_index"], 0, len(evidence) - 1)
                steps.append({"kind": "citation", "evidence_index": index})
            elif step["kind"] == "material":
                _object(step, {"kind", "quote"})
                quote = _text(step["quote"], 1000)
                if quote not in question:
                    _fail("fabricated input-material quote")
                steps.append({"kind": "material", "quote": quote})
            elif step["kind"] == "calculation":
                _object(step, {"kind", "operation", "operands", "places", "rounding"})
                result = calculate(
                    step["operation"],
                    step["operands"],
                    places=step["places"],
                    rounding=step["rounding"],
                )
                _bind_calculation(step["operation"], step["operands"], question, steps)
                steps.append(
                    {
                        "kind": "calculation",
                        "operands": copy.deepcopy(step["operands"]),
                        "result": result,
                    }
                )
            else:
                _fail("free-form model step is not accepted")
        answer = solution["answer"]
        if type(answer) is not dict or type(answer.get("kind")) is not str:
            _fail("invalid answer")
        if answer["kind"] == "calculation":
            _object(answer, {"kind", "step_index", "field", "value"})
            index = _integer(answer["step_index"], 0, len(steps) - 1)
            field = _text(answer["field"], 32)
            value = _text(answer["value"], 64)
            step = steps[index]
            if (
                step["kind"] != "calculation"
                or field not in step["result"]["values"]
                or value != step["result"]["values"][field]
            ):
                _fail("answer disagrees with deterministic arithmetic")
            checked_answer = {
                "kind": "calculation",
                "field": field,
                "value": value,
                "unit": step["result"]["unit"],
            }
        elif answer["kind"] == "evidence":
            _object(answer, {"kind", "evidence_index"})
            index = _integer(answer["evidence_index"], 0, len(evidence) - 1)
            checked_answer = {"kind": "evidence", "quote": evidence[index]["quote"]}
        else:
            _fail("unverifiable free-form answer")
        uncertainties = _ids(solution["uncertainties"], 16)
        if set(uncertainties) - set(REASONS):
            _fail("unknown uncertainty code")
        name = next(
            item["name"]
            for item in catalog["sources"]["candidates"]
            if item["teacher_id"] == teacher_id
        )
        return {
            "status": "evidence_checked",
            "reason": "unverified_conditions",
            "teacher_id": teacher_id,
            "name": name,
            "skill_id": skill_id,
            "method_name": method["name"],
            "conditions": conditions,
            "not_applicable": method["not_applicable"],
            "evidence": evidence,
            "steps": steps,
            "answer": checked_answer,
            "uncertainties": uncertainties,
            "semantic_verified": False,
        }
    except (
        ValueError,
        TypeError,
        KeyError,
        IndexError,
        InvalidOperation,
        RecursionError,
    ):
        return {
            "status": "rejected",
            "reason": "invalid_output",
            "teacher_id": teacher_id
            if type(teacher_id) is str
            and re.fullmatch(r"[a-z][a-z0-9_.-]{0,63}", teacher_id)
            else "unknown",
        }


def _display(value):
    """Escape Markdown/HTML and neutralize model/material links as plain text."""
    text = str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(r"([\\`*_{}\[\]()#!|~])", r"\\\1", text)
    return (
        text.replace("://", ": / /")
        .replace("www.", "www .")
        .replace("@", " @ ")
        .replace("\n", " ")
        .replace("\t", " ")
    )


def _result_block(result):
    name = _display(result["name"])
    lines = [
        "### " + name + "（社区整理，非官方）",
        "方法：" + _display(result["method_name"]),
        "校验范围：仅核对引用存在性、范围及算术；适用性、推导与语义仍待核验。",
    ]
    for condition in result["conditions"]:
        lines.append(
            "条件："
            + _display(condition["condition"])
            + "；题干定位：“"
            + _display(condition["material_quote"])
            + "”"
        )
    lines.append(
        "不适用／易错点："
        + "；".join(_display(item) for item in result["not_applicable"])
    )
    for index, step in enumerate(result["steps"], 1):
        if step["kind"] == "calculation":
            calculation = step["result"]
            inputs = _display(
                json.dumps(step["operands"], ensure_ascii=False, sort_keys=True)
            )
            values = "，".join(
                _display(key) + "=" + value + _display(calculation["unit"])
                for key, value in calculation["values"].items()
            )
            lines.append(
                str(index)
                + ". 受限复算 "
                + calculation["operation"]
                + "；输入 "
                + inputs
                + "；"
                + values
                + "（"
                + str(calculation["places"])
                + " 位小数，"
                + calculation["rounding"]
                + "）"
            )
        elif step["kind"] == "material":
            lines.append(
                str(index)
                + ". 题干原文：“"
                + _display(step["quote"])
                + "”（不据此自动推断结论）"
            )
        else:
            lines.append(
                str(index)
                + ". 对照下列依据 "
                + str(step["evidence_index"] + 1)
                + "；引用不是适用性证明。"
            )
    for index, evidence in enumerate(result["evidence"], 1):
        source_url = quote(evidence["url"], safe=":/%")
        lines.append(
            "依据 "
            + str(index)
            + "：“"
            + _display(evidence["quote"])
            + "”；定位 "
            + _display(evidence["locator"])
            + "；[固定提交来源]("
            + source_url
            + ")；"
            + evidence["evidence_type"]
        )
    answer = result["answer"]
    if answer["kind"] == "calculation":
        lines.append(
            "条件性复算结果（非已证实的题目答案）："
            + answer["field"]
            + "="
            + answer["value"]
            + _display(answer["unit"])
        )
    else:
        lines.append(
            "可核对原文（不输出未经证实的选项或申论事实推断）：“"
            + _display(answer["quote"])
            + "”"
        )
    lines.append(
        "负担："
        + str(len(result["steps"]))
        + " 个可复核步骤、"
        + str(len(result["evidence"]))
        + " 条依据；不作主观难度排名。"
    )
    if result["uncertainties"]:
        lines.append(
            "未解决项：" + "；".join(REASONS[code] for code in result["uncertainties"])
        )
    return "\n".join(lines)


def render(enumeration, results, catalog, *, question="", limit_chars=16000):
    """Revalidate raw envelopes; disclose failures/conflicts and every pending ID."""
    catalog = _catalog(catalog)
    _integer(limit_chars, 2048, 32000)
    _text(question, MAX_QUERY, empty=True)
    _object(
        enumeration,
        {
            "topics",
            "teachers",
            "pending",
            "completed_before",
            "total",
            "offset",
            "limit",
        },
    )
    expected = enumerate_teachers(
        enumeration["topics"],
        catalog,
        limit=enumeration["limit"],
        offset=enumeration["offset"],
    )
    if enumeration != expected:
        _fail("enumeration was changed or teachers omitted")
    _list(results, MAX_TEACHERS)
    _bounded_json(results, 500000)
    if not expected["total"]:
        if results:
            _fail("results provided without matched teachers")
        return {
            "answer": NO_MATCH + "。请补充完整题干、选项及可核验材料。",
            "state": "",
        }
    by_teacher = {}
    expected_ids = {item["teacher_id"] for item in expected["teachers"]}
    for envelope in results:
        _object(
            envelope,
            {"teacher_id", "solution", "provided_skill_ids", "provided_source_ids"},
        )
        key = _identifier(envelope["teacher_id"])
        if key not in expected_ids or key in by_teacher:
            _fail("unexpected or duplicate teacher result")
        by_teacher[key] = verify_solution(
            envelope["solution"],
            key,
            expected["topics"],
            catalog,
            provided_skill_ids=envelope["provided_skill_ids"],
            provided_source_ids=envelope["provided_source_ids"],
            question=question,
        )
    checked = [
        by_teacher[item["teacher_id"]]
        for item in expected["teachers"]
        if item["teacher_id"] in by_teacher
        and by_teacher[item["teacher_id"]]["status"] == "evidence_checked"
    ]
    comparison_keys = set()
    for item in checked:
        answer = item["answer"]
        comparison_keys.add(_bounded_json(answer, 4000))
    lines = [
        "以下仅展示当前已审核目录内的方法与条件性校验结果，不代表老师本人或官方。",
        "目录匹配 "
        + str(expected["total"])
        + " 位；不以多数票认定答案，不声称遍历全网。",
    ]
    if len(comparison_keys) > 1 or any(
        "conflict" in item["uncertainties"] for item in checked
    ):
        lines.append(
            "冲突／口径差异：存在不同结果或明确冲突，尚未解决；不选择多数答案。"
        )
    fingerprints = {}
    methods = {item["skill_id"]: item for item in catalog["methods"]["methods"]}
    for item in checked:
        method = methods[item["skill_id"]]
        fingerprint = _bounded_json(
            [method["applicable"], method["not_applicable"], method["steps"]], 120000
        )
        fingerprints.setdefault(fingerprint, []).append(item["name"])
    for names in fingerprints.values():
        if len(names) > 1:
            lines.append(
                "相同方法步骤与条件："
                + "、".join(_display(name) for name in names)
                + "；不人为制造技巧差异。"
            )
    previous = [item["teacher_id"] for item in expected["completed_before"]]
    pending = [item["teacher_id"] for item in expected["pending"]]
    completed = []
    failed = []
    names = {
        item["teacher_id"]: item["name"] for item in catalog["sources"]["candidates"]
    }
    if previous:
        lines.append(
            "本批之前的目录条目（本次未复核，不等于已完成）："
            + "、".join(_display(names[key]) for key in previous)
        )
    # Reserve the complete pending/failure inventory, never truncate teacher IDs.
    reserve = 200 + sum(
        len(_display(names[item["teacher_id"]])) + len(item["teacher_id"]) + 8
        for item in expected["teachers"] + expected["pending"]
    )
    for teacher in expected["teachers"]:
        key = teacher["teacher_id"]
        result = by_teacher.get(key, {"status": "failed", "reason": "not_returned"})
        if result["status"] == "evidence_checked":
            block = _result_block(result)
        else:
            block = (
                _display(teacher["name"])
                + "："
                + REASONS[result["reason"]]
                + "；该分支未提供已核验解答。"
            )
        if len("\n\n".join(lines)) + len(block) + reserve > limit_chars:
            pending.append(key)
            continue
        lines.append(block)
        completed.append(key)
        if result["status"] != "evidence_checked":
            failed.append(key)
    if failed:
        lines.append(
            "部分失败／跳过："
            + "、".join(_display(names[key]) for key in failed)
            + "。未将缺失分支静默删除。"
        )
    if pending:
        lines.append(
            "待处理／待展示（容量或批次限制）："
            + "、".join(
                _display(names[key]) + " [" + key + "]" for key in sorted(pending)
            )
            + "。请继续这些条目；未声称已比较全部。"
        )
    answer = "\n\n".join(lines)
    if len(answer) > limit_chars:
        _fail(
            "output inventory exceeds limit; increase limit_chars or reduce catalog explicitly"
        )
    state = _bounded_json(
        {
            "schema_version": 1,
            "kind": "teacher_batch",
            "topics": expected["topics"],
            "completed": completed,
            "failed": failed,
            "pending": sorted(pending),
            "previous_unverified": previous,
            "recent_skill_ids": sorted(
                {
                    item["skill_id"]
                    for item in checked
                    if item["teacher_id"] in completed
                }
            ),
        },
        32000,
    )
    return {"answer": answer, "state": state}


def _growth_answer(current, rate, unit):
    values = calculate(
        "growth_from_current", {"current": current, "rate": rate, "unit": unit}
    )["values"]
    return (
        NO_MATCH
        + "。\n\n通用解法（不使用老师 skill）：\n已知现期量 "
        + current
        + unit
        + "，增长率 "
        + rate
        + "。\n基期量 = 现期量 ÷ (1 + 增长率) ≈ "
        + values["base"]
        + unit
        + "。\n增长量 = 现期量 − 基期量 ≈ "
        + values["growth"]
        + unit
        + "。\n以十进制计算，独立四舍五入到小数点后 2 位；分项舍入可能产生尾差。现期量 × 增长率不是该条件下的增长量公式。"
    )


def main(query: str, state: str = "") -> dict:
    """Deterministic empty-catalog Dify entry point; bounded arithmetic followup."""
    fallback = (
        NO_MATCH
        + "。未启用截图识别；请提供单道题的完整文字题干、选项和材料。若需通用解法，请给出可核验输入；当前仅自动计算明确给定现期量与增长率的基期量、增长量。"
    )
    if type(query) is not str or not query.strip() or len(query) > MAX_QUERY:
        return {
            "answer": NO_MATCH
            + "。输入为空或超过 4000 字符，请分次提供单道完整文字题。",
            "state": "",
        }
    query = query.strip()
    previous = None
    invalid_state = False
    if state:
        try:
            _text(state, MAX_STATE)
            previous = json.loads(state)
            _object(
                previous,
                {
                    "schema_version",
                    "kind",
                    "current",
                    "rate",
                    "unit",
                    "turns",
                    "recent_skill_ids",
                },
            )
            if (
                type(previous["schema_version"]) is not int
                or previous["schema_version"] != 1
                or previous["kind"] != "growth"
                or previous["recent_skill_ids"] != []
            ):
                _fail("invalid fallback state")
            _integer(previous["turns"], 1, MAX_TURNS)
            calculate(
                "growth_from_current",
                {key: previous[key] for key in ("current", "rate", "unit")},
            )
        except (ValueError, TypeError, RecursionError):
            previous = None
            invalid_state = True
    elif type(state) is not str:
        invalid_state = True
    followups = {
        "展开",
        "详细步骤",
        "展开步骤",
        "继续",
        "解释一下",
        "为什么不是625",
        "为什么不是 625",
    }
    if query.rstrip("？?。！!") in followups:
        if previous is None or previous["turns"] >= MAX_TURNS:
            reason = (
                "会话状态无效或已达 8 轮上限，已清空。"
                if invalid_state or previous
                else "没有可继续的已验证计算。"
            )
            return {
                "answer": NO_MATCH
                + "。"
                + reason
                + "请重新给出现期量和增长率；不会从会话内容虚构老师或方法。",
                "state": "",
            }
        previous["turns"] += 1
        return {
            "answer": _growth_answer(
                previous["current"], previous["rate"], previous["unit"]
            ),
            "state": _bounded_json(previous, MAX_STATE),
        }
    # Full-match grammar deliberately excludes options, multiple questions,
    # role ambiguity and appended prompt instructions. No heuristic number grab.
    number = r"(?:0|[1-9][0-9]{0,12})(?:\.[0-9]{1,12})?"
    units = "|".join(
        re.escape(unit)
        for unit in sorted(UNITS - {""}, key=lambda item: (-len(item), item))
    )
    pattern = (
        r"(?:已知\s*)?现期量\s*(?:为|是|[:：=])?\s*(?P<current>"
        + number
        + r")\s*(?P<unit>"
        + units
        + r")?\s*[,，、;；]\s*增长率\s*(?:为|是|[:：=])?\s*(?P<rate>-?"
        + number
        + r")\s*[%％]\s*(?:[,，、;；]\s*(?:求|求出|计算)?\s*(?:基期量|基期)(?:和|与|及|、)(?:增长量)(?:是多少|分别是多少)?|[,，、;；]\s*(?:求|求出|计算)?\s*(?:基期量|增长量)(?:是多少)?)?\s*[。？?！!]?"
    )
    match = re.fullmatch(pattern, query)
    if match:
        current, rate, unit = match["current"], match["rate"] + "%", match["unit"] or ""
        try:
            answer = _growth_answer(current, rate, unit)
            new_state = {
                "schema_version": 1,
                "kind": "growth",
                "current": current,
                "rate": rate,
                "unit": unit,
                "turns": 1,
                "recent_skill_ids": [],
            }
            return {"answer": answer, "state": _bounded_json(new_state, MAX_STATE)}
        except ValueError:
            return {
                "answer": NO_MATCH
                + "。数值、单位或增长率超出受限计算范围，请核对现期／基期定义、百分号和题目条件。",
                "state": "",
            }
    if re.search(
        r"(?:展开|优先|偏好|以后|第二|第[一二三四五六七八九十0-9]+位).*老师|老师.*(?:优先|偏好)",
        query,
    ):
        return {
            "answer": NO_MATCH
            + "。当前没有已启用老师或最近可用 skill，无法展开或设置老师偏好；请先提供可审核的方法来源和完整题目。",
            "state": "",
        }
    return {
        "answer": fallback + (" 会话状态无效，已清空。" if invalid_state else ""),
        "state": "",
    }
