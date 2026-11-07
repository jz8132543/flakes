"""Diagnose the installed native retrieval node, without LLM calls or graph edits.

Run locally with Python from this repository. The wrapper streams its source
and reviewed methods to fra0's existing API container. Only query audits and
hit counters may be written. It never substitutes a node, retriever or output.

Exit 1 preserves failed off-topic-empty expectations: inspect isolation_passed
separately. Lexical relevance is not guaranteed by teacher/status filtering.
This diagnostic is deliberately not part of offline verify or LLM acceptance.
"""

import base64
import hashlib
import io
import json
import logging
import sys
from contextlib import redirect_stderr, redirect_stdout

APP_ID = "71afeb8d-4b69-45e0-b91d-eb7701b10059"
DATASET_ID = "07576aa6-2220-450c-b586-c39f69f19682"
NODE_ID = "kg_retrieval"
STAGE = "imports"
RESULTS = []


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def check(value):
    if not value:
        raise AssertionError("Native retrieval contract check failed")


def run():
    global STAGE
    from app_factory import create_app
    from core.workflow.nodes.knowledge_retrieval.entities import (
        KnowledgeRetrievalNodeData,
    )
    from core.workflow.nodes.knowledge_retrieval.knowledge_retrieval_node import (
        KnowledgeRetrievalNode,
    )
    from core.workflow.workflow_entry import WorkflowEntry
    from extensions.ext_database import db
    from graphon.engine_events import NodeRunFailedEvent, NodeRunSucceededEvent
    from graphon.enums import WorkflowNodeExecutionStatus
    from graphon.runtime import VariablePool
    from models import Account, App
    from models.dataset import Dataset, Document, DocumentSegment
    from models.workflow import Workflow
    from services.workflow_node_variables import add_node_input_to_variable_pool
    from sqlalchemy import select
    from sqlalchemy.orm import Session, load_only

    supplied = json.loads(base64.b64decode(sys.argv[2]))
    app_id, dataset_id = supplied["app_id"], supplied["dataset_id"]
    methods = {method["skill_id"]: method for method in supplied["methods"]}
    check(len(methods) == len(supplied["methods"]) == 5)
    for method in methods.values():
        check(method["status"] == "approved")
        check(
            method["content_hash"]
            == hashlib.sha256(
                canonical(
                    {k: v for k, v in method.items() if k != "content_hash"}
                ).encode()
            ).hexdigest()
        )
    STAGE = "app_factory"
    _, flask_app = create_app()
    logging.disable(logging.CRITICAL)
    with flask_app.app_context(), Session(db.engine, expire_on_commit=False) as session:
        STAGE = "read_scoped_app_draft_dataset"
        app = session.scalar(
            select(App)
            .options(
                load_only(
                    App.id,
                    App.tenant_id,
                    App.created_by,
                    App.workflow_id,
                    App.is_public,
                    App.enable_api,
                    App.enable_site,
                )
            )
            .where(App.id == app_id)
        )
        check(
            app is not None
            and app.created_by
            and not app.is_public
            and not app.enable_api
            and not app.enable_site
            and app.workflow_id is None
        )
        account_id = session.scalar(
            select(Account.id).where(Account.id == app.created_by)
        )
        check(account_id is not None)
        workflow = session.scalar(
            select(Workflow)
            .options(
                load_only(
                    Workflow.id,
                    Workflow.tenant_id,
                    Workflow.app_id,
                    Workflow.graph,
                    Workflow.version,
                    Workflow.created_by,
                )
            )
            .where(
                Workflow.app_id == app_id,
                Workflow.tenant_id == app.tenant_id,
                Workflow.version == "draft",
            )
        )
        check(workflow is not None)
        original_graph = workflow.graph
        dataset = session.execute(
            select(Dataset.id, Dataset.tenant_id, Dataset.indexing_technique).where(
                Dataset.id == dataset_id
            )
        ).one()
        check(
            dataset.tenant_id == app.tenant_id
            and dataset.indexing_technique == "economy"
        )
        STAGE = "validate_native_node_data"
        node_config = workflow.get_node_config_by_id(NODE_ID)
        data = KnowledgeRetrievalNodeData.model_validate(
            node_config["data"].model_dump()
        )
        check(data.type == "knowledge-retrieval" and data.dataset_ids == [dataset_id])
        check(data.query_variable_selector == ["kg_select", "query"])
        check(
            data.retrieval_mode == "multiple"
            and not data.multiple_retrieval_config.reranking_enable
        )
        check(data.multiple_retrieval_config.top_k >= len(methods))
        check(data.metadata_filtering_mode == "manual")
        check(data.metadata_filtering_conditions.logical_operator == "and")
        check(
            {
                c.name: (c.comparison_operator, c.value)
                for c in data.metadata_filtering_conditions.conditions
            }
            == {
                "teacher_id": ("is", "{{#kg_extract.teacher_id#}}"),
                "status": ("is", "approved"),
            }
        )
        selectors = (
            KnowledgeRetrievalNode.extract_variable_selector_to_variable_mapping(
                graph_config=workflow.graph_dict, config=node_config
            )
        )
        check(dict(selectors) == {"kg_retrieval.query": ["kg_select", "query"]})
        STAGE = "read_full_segment_baselines"
        rows = session.execute(
            select(
                Document.id,
                Document.doc_metadata,
                DocumentSegment.id.label("segment_id"),
                DocumentSegment.content,
                DocumentSegment.status,
                DocumentSegment.enabled,
            )
            .join(DocumentSegment, DocumentSegment.document_id == Document.id)
            .where(
                Document.dataset_id == dataset_id,
                Document.tenant_id == app.tenant_id,
                DocumentSegment.dataset_id == dataset_id,
            )
        ).all()
        check(len(rows) == len(methods) and len({r.id for r in rows}) == len(rows))
        baseline = {}
        for row in rows:
            metadata = row.doc_metadata
            method = methods.get(metadata.get("skill_id"))
            check(method is not None and row.content == canonical(method))
            check(row.status == "completed" and row.enabled)
            check(
                all(
                    metadata.get(name) == method[name]
                    for name in (
                        "teacher_id",
                        "skill_id",
                        "topic_id",
                        "status",
                        "content_hash",
                    )
                )
            )
            baseline[method["skill_id"]] = {
                "document_id": row.id,
                "segment_id": row.segment_id,
            }

        for skill_id in (
            "li-mengyuan.keyword-extraction",
            "yuan-dong.summary-headings",
        ):
            method = methods[skill_id]
            query = method["examples"][0]["input"]
            for variant, teacher_id in (
                ("seeded", method["teacher_id"]),
                ("off_topic_teacher", "honglingjin"),
                ("absent_teacher", "kaogong-no-such-teacher"),
                ("missing_teacher", None),
                ("extra_debug_inputs", None),
            ):
                STAGE = skill_id + ":" + variant
                pool = VariablePool()
                add_node_input_to_variable_pool(pool, ["kg_select", "query"], query)
                if teacher_id is not None:
                    add_node_input_to_variable_pool(
                        pool, ["kg_extract", "teacher_id"], teacher_id
                    )
                inputs = {"query": query}
                if variant == "extra_debug_inputs":
                    inputs.update(
                        {
                            "teacher_id": method["teacher_id"],
                            "kg_extract.teacher_id": method["teacher_id"],
                            "kg_retrieval.teacher_id": method["teacher_id"],
                            "#kg_extract.teacher_id#": method["teacher_id"],
                            "kg_retrieval.#kg_extract.teacher_id#": method[
                                "teacher_id"
                            ],
                        }
                    )
                node, events = WorkflowEntry.single_step_run(
                    workflow=workflow,
                    node_id=NODE_ID,
                    user_id=account_id,
                    user_inputs=inputs,
                    variable_pool=pool,
                    execution_driver=None,
                )
                check(type(node) is KnowledgeRetrievalNode)
                terminal = [
                    event.node_run_result
                    for event in events
                    if isinstance(event, (NodeRunSucceededEvent, NodeRunFailedEvent))
                ]
                check(
                    len(terminal) == 1
                    and terminal[0].status == WorkflowNodeExecutionStatus.SUCCEEDED
                )
                result = terminal[0]
                check(result.llm_usage.total_tokens == 0)
                records = result.outputs["result"].value
                resolved = node._resolve_metadata_filtering_conditions(
                    data.metadata_filtering_conditions
                )
                values = {
                    condition.name: condition.value for condition in resolved.conditions
                }
                check(
                    values
                    == {
                        "teacher_id": teacher_id or "kg_extract.teacher_id",
                        "status": "approved",
                    }
                )
                ids = []
                for record in records:
                    metadata = record["metadata"]
                    document_metadata = metadata["doc_metadata"]
                    retrieved = methods.get(document_metadata.get("skill_id"))
                    check(retrieved is not None)
                    check(metadata["dataset_id"] == dataset_id)
                    check(
                        metadata["document_id"]
                        == baseline[retrieved["skill_id"]]["document_id"]
                    )
                    check(
                        metadata["segment_id"]
                        == baseline[retrieved["skill_id"]]["segment_id"]
                    )
                    check(record["content"] == canonical(retrieved))
                    check(document_metadata["teacher_id"] == teacher_id)
                    check(
                        all(
                            document_metadata.get(name) == retrieved[name]
                            for name in (
                                "teacher_id",
                                "skill_id",
                                "topic_id",
                                "status",
                                "content_hash",
                            )
                        )
                    )
                    ids.append(
                        {
                            "skill_id": retrieved["skill_id"],
                            **baseline[retrieved["skill_id"]],
                        }
                    )
                if variant == "seeded":
                    check(skill_id in {entry["skill_id"] for entry in ids})
                passed = bool(records) == (variant == "seeded")
                RESULTS.append(
                    {
                        "skill_id": skill_id,
                        "variant": variant,
                        "teacher_id": teacher_id,
                        "hits": len(records),
                        "passed": passed,
                        "isolation_passed": True,
                        "records": ids,
                    }
                )
        STAGE = "confirm_draft_unchanged"
        session.expire(workflow, ["graph"])
        check(workflow.graph == original_graph)
        return {
            "scope": "native-retrieval-diagnostic",
            "passed": all(r["passed"] for r in RESULTS),
            "isolation_passed": True,
            "app_id": app_id,
            "workflow_id": workflow.id,
            "dataset_id": dataset_id,
            "node_id": NODE_ID,
            "llm_tokens": 0,
            "draft_unchanged": True,
            "results": RESULTS,
        }


def main():
    logging.disable(logging.CRITICAL)
    if sys.argv[1:2] != ["--inside-dify"]:
        import argparse
        import subprocess
        import uuid
        from pathlib import Path

        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("--app-id", type=uuid.UUID, default=APP_ID)
        parser.add_argument("--dataset-id", type=uuid.UUID, default=DATASET_ID)
        args = parser.parse_args()
        try:
            root = Path(__file__).resolve().parents[1]
            methods = json.loads((root / "conf/dify-kaogong/methods.json").read_text())[
                "methods"
            ]
            supplied = {
                "app_id": str(args.app_id),
                "dataset_id": str(args.dataset_id),
                "methods": methods,
            }
            payload = base64.b64encode(
                json.dumps(supplied, ensure_ascii=False).encode()
            ).decode()
            child = subprocess.run(
                [
                    "ssh",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "ConnectTimeout=8",
                    "fra0",
                    "sudo -n podman exec -i dify-api /app/api/.venv/bin/python -B - --inside-dify "
                    + payload,
                ],
                input=Path(__file__).read_bytes(),
                capture_output=True,
                timeout=120,
                check=False,
            )
            print(json.dumps(json.loads(child.stdout), sort_keys=True))
            return child.returncode
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            print(
                json.dumps(
                    {
                        "passed": False,
                        "stage": "local_wrapper",
                        "error_type": type(error).__name__,
                    }
                )
            )
            return 1
    try:
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            report = run()
    except Exception as error:  # noqa: BLE001 -- native ORM/SDK errors may contain credentials
        report = {
            "passed": False,
            "stage": STAGE,
            "error_type": type(error).__name__,
            "results": RESULTS,
        }
    print(json.dumps(report, sort_keys=True))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
