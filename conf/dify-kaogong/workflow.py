"""Build auditable Dify Chatflows without remote side effects.

build_workflow retains the original empty-catalog graph. The separate teacher
builder uses native LLM, retrieval and Iteration nodes. Supplied Python and
catalogs must be trusted; syntax/interface validation is not a code security
audit, evidence audit or sandbox. Building does not establish online readiness.

Compatibility was inspected in fra0's installed Dify 1.19.0 (DSL 0.7.0):
* /app/api/constants/dsl_version.py
* /app/api/services/app_dsl_service.py
* /app/api/factories/variable_factory.py
* /app/api/.venv/lib/python3.13/site-packages/graphon/entities/graph_config.py
* graphon/nodes/{start,code,answer}/entities.py (under that site-packages path)
* graphon/nodes/variable_assigner/v2/{entities,enums}.py

The authenticated preview endpoint is:
POST /console/api/apps/<app_id>/advanced-chat/workflows/draft/run
with {"inputs": {}, "query": "...", "files": []}.
Reuse the returned conversation_id on later turns. The endpoint forces SSE and
dispatches a worker task; it is not a read-only validation endpoint. Installed
AdvancedChatAppGenerator defaults auto_generate_conversation_name to False, and
MessageBasedAppGenerator._init_generate_records uses model_provider/model_id=None
for advanced chat. No default LLM is required by these inspected paths. A healthy
worker and Code sandbox are still required; source checks are not a live preview.

The returned dict can be serialized with json.dumps: JSON is a YAML subset.
Importing DSL alone does not disable an app's public site/API or publish it.
Those application-level permissions belong to the separate integration step.
"""

import ast
import itertools
import json
import re
import sys
import uuid

DSL_VERSION = "0.7.0"
DIFY_VERSION = "1.19.0"
DIFY_REVISION = "8e689e868b63b6dd2b449d0eb568ca5cc7127759"
API_IMAGE_DIGEST = (
    "sha256:0d67842aedcb9b5884f75b88c4a5dd812e637916bff1ca892831f7ace2f3204f"
)
WEB_IMAGE_DIGEST = (
    "sha256:f5f1ad000d6a268ae6b29b84c5095069fbd5994cbe43f937a3d32caa00038b4c"
)

_START, _CODE, _ASSIGN, _ANSWER = (
    "1793891382490",
    "1793891382491",
    "1793891382492",
    "1793891382493",
)
_STATE_SELECTOR = ("conversation", "kaogong_state")
_DSL_MAX_SIZE = 10 * 1024 * 1024  # Installed services/dsl_content.py, UTF-8 bytes.


def _validate_code(code: str) -> None:
    if type(code) is not str or not code.strip():
        raise ValueError("Code must be nonempty self-contained Python source")
    try:
        tree = ast.parse(code, filename="<kaogong-runtime>")
        compile(tree, "<kaogong-runtime>", "exec")
    except (SyntaxError, ValueError, TypeError) as exc:
        raise ValueError("Code must be valid Python source") from exc

    mains = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "main"
    ]
    if len(mains) != 1 or not isinstance(mains[0], ast.FunctionDef):
        raise ValueError(
            "Code must define one synchronous top-level main(query, state='')"
        )
    main = mains[0]
    args = main.args
    if (
        main.decorator_list
        or args.posonlyargs
        or args.kwonlyargs
        or args.vararg
        or args.kwarg
        or [arg.arg for arg in args.args] != ["query", "state"]
        or len(args.defaults) != 1
        or not isinstance(args.defaults[0], ast.Constant)
        or args.defaults[0].value != ""
    ):
        raise ValueError(
            "Code main must accept exactly query and state, with state defaulting to ''"
        )

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules = [alias.name.split(".")[0] for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            if node.level or not node.module:
                raise ValueError("Code must not depend on relative/local imports")
            modules = [node.module.split(".")[0]]
        else:
            continue
        if any(module not in sys.stdlib_module_names for module in modules):
            raise ValueError(
                "Code imports must be Python standard-library modules only"
            )


def _template(code: str) -> dict:
    data = [
        {"type": "start", "version": "1", "title": "\u5f00\u59cb", "variables": []},
        {
            "type": "code",
            "version": "1",
            "title": "\u7a7a\u8d44\u6599\u5e93\u5904\u7406",
            "code_language": "python3",
            "code": code,
            "dependencies": [],
            "variables": [
                {"variable": "query", "value_selector": ["sys", "query"]},
                {"variable": "state", "value_selector": list(_STATE_SELECTOR)},
            ],
            "outputs": {
                "answer": {"type": "string", "children": None},
                "state": {"type": "string", "children": None},
            },
        },
        {
            "type": "assigner",
            "version": "2",
            "title": "\u4fdd\u5b58\u4f1a\u8bdd\u72b6\u6001",
            "items": [
                {
                    "variable_selector": list(_STATE_SELECTOR),
                    "input_type": "variable",
                    "operation": "over-write",
                    "value": [_CODE, "state"],
                }
            ],
        },
        {
            "type": "answer",
            "version": "1",
            "title": "\u56de\u7b54",
            "answer": "{{#" + _CODE + ".answer#}}",
        },
    ]
    ids = (_START, _CODE, _ASSIGN, _ANSWER)
    nodes = [
        {
            "id": node_id,
            "type": "custom",
            "data": node_data,
            "position": {"x": 80 + index * 320, "y": 240},
            "width": 244,
            "height": 100,
            "sourcePosition": "right",
            "targetPosition": "left",
        }
        for index, (node_id, node_data) in enumerate(zip(ids, data))
    ]
    edges = [
        {
            "id": source + "-source-" + target + "-target",
            "type": "custom",
            "source": source,
            "sourceHandle": "source",
            "target": target,
            "targetHandle": "target",
            "data": {
                "sourceType": data[index]["type"],
                "targetType": data[index + 1]["type"],
                "isInIteration": False,
                "isInLoop": False,
            },
        }
        for index, (source, target) in enumerate(itertools.pairwise(ids))
    ]
    return {
        "kind": "app",
        "version": DSL_VERSION,
        "dependencies": [],
        "app": {
            "name": "\u8003\u516c\u65b9\u6cd5\u6838\u9a8c\uff08\u8d44\u6599\u5f85\u5ba1\uff09",
            "description": (
                "\u5f53\u524d\u4ec5\u63d0\u4f9b\u6587\u5b57\u9898\u65e0\u5339\u914d\u5206\u652f\uff1b"
                "\u6ca1\u6709\u542f\u7528\u5df2\u5ba1\u6838\u8001\u5e08\u65b9\u6cd5\uff0c"
                "\u4e0d\u662f\u591a\u8001\u5e08\u6bd4\u8f83\u5de5\u4f5c\u6d41\u3002"
                "\u4ec5\u4f9b\u767b\u5f55\u540e\u7684\u5de5\u4f5c\u5ba4\u9884\u89c8\u3002"
            ),
            "mode": "advanced-chat",
            "icon_type": "emoji",
            "icon": "K",
            "icon_background": "#E8E2D5",
            "use_icon_as_answer_icon": False,
        },
        "workflow": {
            "environment_variables": [],
            "conversation_variables": [
                {
                    "id": "3f099ffe-bdf7-5fb2-9499-6f7479f2dd08",
                    "name": "kaogong_state",
                    "description": "Bounded runtime JSON state for the current conversation only.",
                    "value_type": "string",
                    "value": "",
                    "selector": list(_STATE_SELECTOR),
                }
            ],
            "features": {
                "opening_statement": (
                    "\u5f53\u524d\u5df2\u5ba1\u6838\u8d44\u6599\u5e93\u4e2d\u672a\u627e\u5230"
                    "\u9002\u7528\u7684\u8001\u5e08\u65b9\u6cd5\u3002"
                    "\u8bf7\u7c98\u8d34\u6587\u5b57\u9898\uff1b\u4e0d\u652f\u6301\u622a\u56fe"
                    "\u6216\u6587\u4ef6\u4e0a\u4f20\u3002"
                    "\u901a\u7528\u89e3\u6cd5\u4e0d\u4f7f\u7528\u8001\u5e08 skill\u3002"
                ),
                "suggested_questions": [],
                "suggested_questions_after_answer": {"enabled": False},
                "retriever_resource": {"enabled": False},
                "sensitive_word_avoidance": {"enabled": False},
                "speech_to_text": {"enabled": False},
                "text_to_speech": {
                    "enabled": False,
                    "voice": "",
                    "language": "",
                    "autoPlay": "disabled",
                },
                "file_upload": {
                    "enabled": False,
                    "allowed_file_types": [],
                    "allowed_file_extensions": [],
                    "allowed_file_upload_methods": [],
                    "number_limits": 0,
                },
            },
            "graph": {
                "nodes": nodes,
                "edges": edges,
                "viewport": {"x": 0, "y": 0, "zoom": 0.8},
            },
        },
    }


def _check_contract(actual: object, expected: object, path: str) -> None:
    # Exact shapes also reject unknown credential/model fields and extra nodes.
    # Do not include actual values (possibly secret) in validation errors.
    if type(actual) is not type(expected):
        raise ValueError(f"Unexpected type at {path}")
    if isinstance(expected, dict):
        if actual.keys() != expected.keys():
            raise ValueError(f"Unexpected fields at {path}")
        for key, value in expected.items():
            _check_contract(actual[key], value, f"{path}.{key}")
    elif isinstance(expected, list):
        if len(actual) != len(expected):
            raise ValueError(f"Unexpected length at {path}")
        for index, value in enumerate(expected):
            _check_contract(actual[index], value, f"{path}[{index}]")
    elif actual != expected:
        raise ValueError(f"Unexpected value at {path}")


def build_workflow(code: str) -> dict:
    """Embed trusted runtime source verbatim in a fresh DSL dict; never execute it.

    This entry point has no catalog argument intentionally. Adding approved
    methods requires a separately verified teacher graph, not this fallback.
    """
    dsl = _template(code)
    validate_workflow(dsl)
    return dsl


def validate_workflow(dsl: dict) -> None:
    """Validate this builder's strict artifact contract, not arbitrary Dify DSL.

    Fail closed on altered topology, state selectors/types, enabled features,
    extra dependencies or fields, and incompatible DSL/node versions. Runtime
    answer semantics and absence of secrets inside supplied code need separate
    review/tests. Re-exported or edited Dify DSL is not silently normalized.
    """
    if type(dsl) is not dict:
        raise ValueError("DSL must be a dictionary")
    try:
        code = dsl["workflow"]["graph"]["nodes"][1]["data"]["code"]
    except (KeyError, IndexError, TypeError) as exc:
        raise ValueError("Missing empty-catalog Code node") from exc
    _validate_code(code)
    _check_contract(dsl, _template(code), "dsl")
    # Default JSON encoding is intentionally conservative for non-ASCII source.
    if len(json.dumps(dsl, allow_nan=False).encode("utf-8")) > _DSL_MAX_SIZE:
        raise ValueError("Serialized DSL exceeds the installed 10 MiB import limit")


_TEACHER_MARKER = "\n\n# kaogong-native-teacher-v1\n"
_TEACHER_MAX_TEXT = 80_000
_TEACHER_MAX_ITEMS = 30
_TEACHER_FUNCTIONS = {
    "teacher_prepare": ["query", "state"],
    "teacher_select": ["classification", "question", "request", "state"],
    "teacher_extract": ["item"],
    "teacher_evidence": ["teacher_id", "result", "context"],
    "teacher_verify": ["teacher_id", "solution", "review", "evidence", "context"],
    "teacher_serialize": ["results", "context"],
    "teacher_render": ["context", "results", "general", "general_review"],
}


def _teacher_inputs(code: str, catalog: dict, binding: dict) -> dict:
    """Validate public binding data without executing the supplied runtime."""
    if type(code) is not str or not code.strip() or _TEACHER_MARKER in code:
        raise ValueError("Invalid teacher runtime source")
    try:
        tree = ast.parse(code, filename="<kaogong-teacher-runtime>")
        compile(tree, "<kaogong-teacher-runtime>", "exec")
    except (SyntaxError, ValueError, TypeError) as exc:
        raise ValueError("Teacher runtime must be valid Python source") from exc
    for name, arguments in _TEACHER_FUNCTIONS.items():
        functions = [
            node
            for node in tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == name
        ]
        if len(functions) != 1 or not isinstance(functions[0], ast.FunctionDef):
            raise ValueError("Missing synchronous teacher helper: " + name)
        function = functions[0]
        if (
            function.decorator_list
            or function.args.posonlyargs
            or function.args.kwonlyargs
            or function.args.vararg
            or function.args.kwarg
            or [argument.arg for argument in function.args.args] != arguments
        ):
            raise ValueError("Unexpected teacher helper signature: " + name)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules = [alias.name.split(".")[0] for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            if node.level or not node.module:
                raise ValueError("Teacher runtime cannot use relative imports")
            modules = [node.module.split(".")[0]]
        else:
            continue
        if any(module not in sys.stdlib_module_names for module in modules):
            raise ValueError("Teacher runtime imports must be standard library only")

    if (
        type(catalog) is not dict
        or set(catalog) != {"taxonomy", "sources", "methods"}
        or any(type(value) is not dict for value in catalog.values())
    ):
        raise ValueError("Expected raw taxonomy, sources and methods envelopes")
    if (
        type(binding) is not dict
        or not {"dataset_id", "retrieval_top_k", "provider", "model"} <= set(binding)
        or set(binding)
        - {"dataset_id", "retrieval_top_k", "provider", "model", "dependencies"}
    ):
        raise ValueError("Invalid teacher resource binding fields")
    dataset_id = binding["dataset_id"]
    try:
        if type(dataset_id) is not str or str(uuid.UUID(dataset_id)) != dataset_id:
            raise ValueError("Invalid dataset UUID")
    except (ValueError, AttributeError) as exc:
        raise ValueError("Invalid dataset UUID") from exc
    top_k = binding["retrieval_top_k"]
    if type(top_k) is not int or not 1 <= top_k <= _TEACHER_MAX_ITEMS:
        raise ValueError("Retrieval capacity must be between 1 and 30")
    methods = catalog["methods"].get("methods")
    if type(methods) is not list or any(type(method) is not dict for method in methods):
        raise ValueError("Invalid method catalog envelope")
    if sum(method.get("status") == "approved" for method in methods) > top_k:
        raise ValueError("Retrieval capacity cannot cover all approved method chunks")
    if (
        type(binding["provider"]) is not str
        or re.fullmatch(
            r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", binding["provider"]
        )
        is None
        or type(binding["model"]) is not str
        or not binding["model"].strip()
        or len(binding["model"]) > 200
        or any(ord(char) < 32 for char in binding["model"])
    ):
        raise ValueError("Invalid teacher model identity")
    dependencies = binding.get("dependencies", [])
    if type(dependencies) is not list or len(dependencies) > 1:
        raise ValueError("Expected at most one native model plugin dependency")
    for dependency in dependencies:
        if (
            type(dependency) is not dict
            or set(dependency) - {"type", "value", "current_identifier"}
            or dependency.get("type") != "marketplace"
            or type(dependency.get("value")) is not dict
            or set(dependency["value"])
            - {"marketplace_plugin_unique_identifier", "version"}
            or dependency.get("current_identifier") is not None
        ):
            raise ValueError("Invalid native marketplace dependency")
        identifier = dependency["value"].get("marketplace_plugin_unique_identifier")
        if (
            type(identifier) is not str
            or not identifier.startswith(
                "/".join(binding["provider"].split("/")[:2]) + ":"
            )
            or len(identifier) > 512
            or re.fullmatch(r"[A-Za-z0-9_./:@+-]+", identifier) is None
            or (
                dependency["value"].get("version") is not None
                and type(dependency["value"]["version"]) is not str
            )
        ):
            raise ValueError("Invalid pinned model plugin dependency")
    try:
        encoded = json.dumps(
            {"catalog": catalog, "binding": binding},
            ensure_ascii=True,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        manifest = json.loads(encoded)
    except (ValueError, TypeError, RecursionError) as exc:
        raise ValueError("Teacher inputs must be finite JSON data") from exc
    manifest["binding"].setdefault("dependencies", [])
    return manifest


def _teacher_code(
    code: str, manifest: dict, arguments: list[str], expression: str
) -> str:
    payload = json.dumps(
        manifest, sort_keys=True, separators=(",", ":"), allow_nan=False
    )
    return (
        code
        + _TEACHER_MARKER
        + "import json as _kg_json\n"
        + "_KG_MANIFEST = _kg_json.loads("
        + repr(payload)
        + ")\n"
        + "KAOGONG_CATALOG = _KG_MANIFEST['catalog']\n\n"
        + "def main("
        + ", ".join(arguments)
        + "):\n"
        + "    result = "
        + expression
        + "\n"
        + "    if not isinstance(result, dict):\n"
        + "        raise ValueError('invalid runtime result')\n"
        + "    for value in result.values():\n"
        + "        if isinstance(value, str) and len(value) > "
        + str(_TEACHER_MAX_TEXT)
        + ":\n"
        + "            raise ValueError('runtime text capacity exceeded')\n"
        + "        if isinstance(value, list) and len(value) > "
        + str(_TEACHER_MAX_ITEMS)
        + ":\n"
        + "            raise ValueError('runtime array capacity exceeded')\n"
        + "    return result\n"
    )


def _teacher_template(code: str, manifest: dict) -> dict:
    prompts = {}
    prompt_names = {
        "CLASSIFY_PROMPT",
        "SOLVE_PROMPT",
        "REVIEW_PROMPT",
        "GENERAL_PROMPT",
    }
    for node in ast.parse(code).body:
        if (
            isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id in prompt_names | {"GENERAL_REVIEW_PROMPT"}
        ):
            name = node.targets[0].id
            if (
                name in prompts
                or not isinstance(node.value, ast.Constant)
                or type(node.value.value) is not str
            ):
                raise ValueError("Teacher prompts must be unique literal strings")
            prompts[name] = node.value.value
    if not prompt_names <= set(prompts) or any(
        not prompt.strip() or len(prompt) > _TEACHER_MAX_TEXT
        for prompt in prompts.values()
    ):
        raise ValueError("Missing or oversized teacher prompt contract")

    binding = manifest["binding"]
    dsl = _template("")
    dsl["dependencies"] = json.loads(json.dumps(binding["dependencies"]))
    dsl["app"].update(
        {
            "name": "\u8003\u516c\u591a\u8001\u5e08\u65b9\u6cd5\u6838\u9a8c",
            "description": (
                "\u6309\u8001\u5e08\u68c0\u7d22\u5df2\u5ba1\u6838\u793e\u533a\u65b9\u6cd5\uff0c"
                "\u72ec\u7acb\u89e3\u9898\u4e0e\u590d\u6838\uff1b\u975e\u5b98\u65b9\uff0c"
                "\u7ed3\u679c\u4ecd\u9700\u6838\u9a8c\u3002\u4ec5\u5de5\u4f5c\u5ba4\u9884\u89c8\u3002"
            ),
        }
    )
    dsl["workflow"]["features"]["opening_statement"] = (
        "\u8bf7\u63d0\u4f9b\u5b8c\u6574\u6587\u5b57\u9898\u3001\u9009\u9879\u548c\u6750\u6599\u3002"
        "\u8001\u5e08\u65b9\u6cd5\u4ec5\u6765\u81ea\u5df2\u5ba1\u6838\u793e\u533a\u8d44\u6599\uff0c"
        "\u5e76\u975e\u8001\u5e08\u672c\u4eba\u6216\u5b98\u65b9\u80cc\u4e66\u3002"
        "\u4e0d\u652f\u6301\u622a\u56fe\u6216\u6587\u4ef6\u4e0a\u4f20\u3002"
    )
    nodes = []
    edges = []
    root_ids = [
        "kg_start",
        "kg_prepare",
        "kg_classifier",
        "kg_select",
        "kg_iteration",
        "kg_serialize",
        "kg_general",
        "kg_general_review",
        "kg_render",
        "kg_assign",
        "kg_answer",
    ]
    inner_ids = [
        "kg_iter_start",
        "kg_extract",
        "kg_retrieval",
        "kg_evidence",
        "kg_solve",
        "kg_review",
        "kg_verify",
    ]

    def add_node(node_id: str, data: dict) -> None:
        inside = node_id in inner_ids
        index = (inner_ids if inside else root_ids).index(node_id)
        node = {
            "id": node_id,
            "type": "custom",
            "data": {"version": "1", **data},
            "position": {
                "x": 80 + index * 320 + (2240 if not inside and index > 4 else 0),
                "y": 100 if inside else 240,
            },
            "width": 244,
            "height": 100,
            "sourcePosition": "right",
            "targetPosition": "left",
        }
        if inside:
            node.update({"parentId": "kg_iteration", "extent": "parent"})
            node["data"].update(
                {
                    "container_id": "kg_iteration",
                    "iteration_id": "kg_iteration",
                    "isInIteration": True,
                }
            )
        if node_id == "kg_iteration":
            node.update({"width": 2320, "height": 300})
            node["data"].update({"width": 2320, "height": 300})
        elif node_id == "kg_iter_start":
            node.update(
                {
                    "type": "custom-iteration-start",
                    "width": 44,
                    "height": 48,
                    "selectable": False,
                }
            )
        nodes.append(node)

    def add_code(
        node_id: str, function: str, variables: dict, outputs: dict, title: str
    ) -> None:
        arguments = list(variables)
        add_node(
            node_id,
            {
                "type": "code",
                "title": title,
                "code_language": "python3",
                "dependencies": [],
                "retry_config": {
                    "retry_enabled": True,
                    "max_retries": 2,
                    "retry_interval": 1000,
                },
                "variables": [
                    {"variable": name, "value_selector": selector}
                    for name, selector in variables.items()
                ],
                "outputs": {
                    name: {"type": output_type, "children": None}
                    for name, output_type in outputs.items()
                },
                "code": _teacher_code(
                    code,
                    manifest,
                    arguments,
                    function + "(" + ", ".join(arguments) + ")",
                ),
            },
        )

    def add_llm(
        node_id: str, prompt: str, user: str, max_tokens: int, title: str
    ) -> None:
        teacher_branch = node_id in {"kg_solve", "kg_review"}
        add_node(
            node_id,
            {
                "type": "llm",
                "title": title,
                "model": {
                    "provider": binding["provider"],
                    "name": binding["model"],
                    "mode": "chat",
                    "completion_params": {"max_tokens": max_tokens},
                },
                "prompt_template": [
                    {"role": "system", "text": prompt},
                    {"role": "user", "text": user},
                ],
                "context": {"enabled": False, "variable_selector": []},
                "vision": {"enabled": False},
                "memory": None,
                "structured_output_switch_on": False,
                "reasoning_format": "separated",
                "retry_config": {
                    "retry_enabled": True,
                    "max_retries": 5 if teacher_branch else 2,
                    "retry_interval": 5000 if teacher_branch else 2000,
                },
                "error_strategy": "default-value",
                "default_value": [
                    {
                        "key": "text",
                        "type": "string",
                        "value": '{"status":"failed","reason":"model_failure"}',
                    }
                ],
            },
        )

    add_node("kg_start", {"type": "start", "title": "\u5f00\u59cb", "variables": []})
    add_code(
        "kg_prepare",
        "teacher_prepare",
        {
            "query": ["sys", "query"],
            "state": list(_STATE_SELECTOR),
        },
        {"question": "string", "request": "string", "state": "string"},
        "\u6574\u7406\u539f\u9898",
    )
    taxonomy = json.dumps(
        manifest["catalog"]["taxonomy"], ensure_ascii=False, sort_keys=True
    )
    add_llm(
        "kg_classifier",
        prompts["CLASSIFY_PROMPT"] + "\nAllowed taxonomy:\n" + taxonomy,
        "Question:\n{{#kg_prepare.question#}}\nRequest:\n{{#kg_prepare.request#}}",
        4096,
        "\u9898\u578b\u4e0e\u5b8c\u6574\u6027",
    )
    add_code(
        "kg_select",
        "teacher_select",
        {
            "classification": ["kg_classifier", "text"],
            "question": ["kg_prepare", "question"],
            "request": ["kg_prepare", "request"],
            "state": ["kg_prepare", "state"],
        },
        {"teachers": "array[object]", "context": "string", "query": "string"},
        "\u679a\u4e3e\u5168\u90e8\u5339\u914d\u8001\u5e08",
    )
    add_node(
        "kg_iteration",
        {
            "type": "iteration",
            "title": "\u6309\u8001\u5e08\u72ec\u7acb\u5904\u7406",
            "start_node_id": "kg_iter_start",
            "iterator_selector": ["kg_select", "teachers"],
            "output_selector": ["kg_verify", "result"],
            "iterator_input_type": "array[object]",
            "output_type": "array[object]",
            "is_parallel": True,
            "parallel_nums": 3,
            "error_handle_mode": "continue-on-error",
            "flatten_output": False,
        },
    )
    add_node("kg_iter_start", {"type": "iteration-start", "title": ""})
    add_code(
        "kg_extract",
        "teacher_extract",
        {"item": ["kg_iteration", "item"]},
        {"teacher_id": "string"},
        "\u53d6\u5f97\u8001\u5e08\u6807\u8bc6",
    )
    add_node(
        "kg_retrieval",
        {
            "type": "knowledge-retrieval",
            "title": "\u8001\u5e08\u4e0e\u5ba1\u6838\u72b6\u6001\u786c\u8fc7\u6ee4",
            "dataset_ids": [binding["dataset_id"]],
            "query_variable_selector": ["kg_select", "query"],
            "retrieval_mode": "multiple",
            "multiple_retrieval_config": {
                "top_k": binding["retrieval_top_k"],
                "reranking_enable": False,
                "reranking_mode": "reranking_model",
                "score_threshold": None,
            },
            "metadata_filtering_mode": "manual",
            "metadata_filtering_conditions": {
                "logical_operator": "and",
                "conditions": [
                    {
                        "id": "kg-filter-teacher",
                        "name": "teacher_id",
                        "comparison_operator": "is",
                        "value": "{{#kg_extract.teacher_id#}}",
                    },
                    {
                        "id": "kg-filter-approved",
                        "name": "status",
                        "comparison_operator": "is",
                        "value": "approved",
                    },
                ],
            },
            "vision": {"enabled": False},
        },
    )
    add_code(
        "kg_evidence",
        "teacher_evidence",
        {
            "teacher_id": ["kg_extract", "teacher_id"],
            "result": ["kg_retrieval", "result"],
            "context": ["kg_select", "context"],
        },
        {"evidence": "string"},
        "\u6838\u5bf9\u65b9\u6cd5\u4e0e\u6765\u6e90",
    )
    own_evidence = (
        "Question:\n{{#kg_prepare.question#}}\nTeacher ID:\n{{#kg_extract.teacher_id#}}"
        "\nAudited evidence:\n{{#kg_evidence.evidence#}}"
    )
    add_llm(
        "kg_solve",
        prompts["SOLVE_PROMPT"],
        own_evidence,
        8192,
        "\u72ec\u7acb\u89e3\u9898",
    )
    add_llm(
        "kg_review",
        prompts["REVIEW_PROMPT"],
        own_evidence + "\nProposed solution:\n{{#kg_solve.text#}}",
        4096,
        "\u72ec\u7acb\u590d\u6838",
    )
    add_code(
        "kg_verify",
        "teacher_verify",
        {
            "teacher_id": ["kg_extract", "teacher_id"],
            "solution": ["kg_solve", "text"],
            "review": ["kg_review", "text"],
            "evidence": ["kg_evidence", "evidence"],
            "context": ["kg_select", "context"],
        },
        {"result": "object"},
        "\u7a0b\u5e8f\u8bc1\u636e\u4e0e\u7b97\u672f\u6821\u9a8c",
    )
    add_code(
        "kg_serialize",
        "teacher_serialize",
        {
            "results": ["kg_iteration", "output"],
            "context": ["kg_select", "context"],
        },
        {"results": "string"},
        "\u4fdd\u7559\u5168\u90e8\u8001\u5e08\u7ed3\u679c",
    )
    general_context = "Context:\n{{#kg_select.context#}}\nTeacher results:\n{{#kg_serialize.results#}}"
    add_llm(
        "kg_general",
        prompts["GENERAL_PROMPT"],
        general_context,
        8192,
        "\u72ec\u7acb\u901a\u7528\u5206\u652f",
    )
    add_llm(
        "kg_general_review",
        prompts.get("GENERAL_REVIEW_PROMPT", prompts["REVIEW_PROMPT"]),
        general_context
        + "\nGeneral solution (not a teacher method):\n{{#kg_general.text#}}",
        4096,
        "\u901a\u7528\u5206\u652f\u590d\u6838",
    )
    add_code(
        "kg_render",
        "teacher_render",
        {
            "context": ["kg_select", "context"],
            "results": ["kg_serialize", "results"],
            "general": ["kg_general", "text"],
            "general_review": ["kg_general_review", "text"],
        },
        {"answer": "string", "state": "string"},
        "\u5e76\u5217\u5c55\u793a\u4e0e\u5931\u8d25\u8bf4\u660e",
    )
    add_node(
        "kg_assign",
        {
            "type": "assigner",
            "version": "2",
            "title": "\u4fdd\u5b58\u672c\u9898\u72b6\u6001",
            "items": [
                {
                    "variable_selector": list(_STATE_SELECTOR),
                    "input_type": "variable",
                    "operation": "over-write",
                    "value": ["kg_render", "state"],
                }
            ],
        },
    )
    add_node(
        "kg_answer",
        {"type": "answer", "title": "\u56de\u7b54", "answer": "{{#kg_render.answer#}}"},
    )
    by_id = {node["id"]: node for node in nodes}
    for scope in (root_ids, inner_ids):
        for source, target in itertools.pairwise(scope):
            edges.append(
                {
                    "id": source + "-source-" + target + "-target",
                    "type": "custom",
                    "source": source,
                    "sourceHandle": "source",
                    "target": target,
                    "targetHandle": "target",
                    "data": {
                        "sourceType": by_id[source]["data"]["type"],
                        "targetType": by_id[target]["data"]["type"],
                        "isInIteration": source in inner_ids,
                        "isInLoop": False,
                    },
                }
            )
    dsl["workflow"]["graph"] = {
        "nodes": nodes,
        "edges": edges,
        "viewport": {"x": 0, "y": 0, "zoom": 0.6},
    }
    return dsl


def validate_teacher_workflow(dsl: dict) -> None:
    """Reject changes to the native teacher graph, including evidence boundaries.

    This validates this builder's artifact, not arbitrary Dify exports. The
    embedded runtime is parsed, never executed. Resource ownership, the actual
    keyword-index chunk count, model health and evidence approval require the
    caller's separate checks.
    """
    if type(dsl) is not dict:
        raise ValueError("DSL must be a dictionary")
    try:
        nodes = dsl["workflow"]["graph"]["nodes"]
        prepare = next(node for node in nodes if node["id"] == "kg_prepare")
        embedded = prepare["data"]["code"]
        source, marker, wrapper = embedded.partition(_TEACHER_MARKER)
        if not marker:
            raise ValueError("Missing teacher runtime manifest")
        tree = ast.parse(wrapper)
        assignments = [
            node
            for node in tree.body
            if isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id == "_KG_MANIFEST"
        ]
        if len(assignments) != 1:
            raise ValueError("Invalid teacher runtime manifest")
        value = assignments[0].value
        if (
            not isinstance(value, ast.Call)
            or len(value.args) != 1
            or value.keywords
            or not isinstance(value.args[0], ast.Constant)
            or type(value.args[0].value) is not str
        ):
            raise ValueError("Invalid teacher runtime manifest")
        manifest = json.loads(value.args[0].value)
        if type(manifest) is not dict or set(manifest) != {"catalog", "binding"}:
            raise ValueError("Invalid teacher runtime manifest")
        normalized = _teacher_inputs(source, manifest["catalog"], manifest["binding"])
    except (
        KeyError,
        IndexError,
        StopIteration,
        AttributeError,
        TypeError,
        SyntaxError,
    ) as exc:
        raise ValueError("Invalid teacher graph or embedded runtime") from exc
    expected = _teacher_template(source, normalized)
    _check_contract(dsl, expected, "dsl")
    if len(json.dumps(dsl, allow_nan=False).encode("utf-8")) > _DSL_MAX_SIZE:
        raise ValueError("Serialized DSL exceeds the installed 10 MiB import limit")


def build_teacher_workflow(code: str, catalog: dict, binding: dict) -> dict:
    """Build the native teacher graph from audited code and raw catalog envelopes.

    binding contains dataset_id, retrieval_top_k, provider, model, and optional
    native marketplace dependencies. retrieval_top_k must cover every keyword
    index chunk in the selected immutable dataset, not just this teacher's cards.
    The builder cannot verify that remote invariant and performs no I/O.
    """
    manifest = _teacher_inputs(code, catalog, binding)
    dsl = _teacher_template(code, manifest)
    validate_teacher_workflow(dsl)
    return dsl
