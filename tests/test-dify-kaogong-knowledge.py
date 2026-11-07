"""Hermetic importer contracts: python3 -B tests/test-dify-kaogong-knowledge.py.

The synthetic server, generated credentials, and failure injections below are
engineering fixtures, not proof of native Dify indexing or teaching quality.
Success cases use detached copies of the repository's reviewed method cards;
their approval flags and hashes are never changed or written back. Intentionally
invalid copies exercise rejection gates. No production credential is read.

Only HTTP transports are replaced. The actual importer, metadata/readback gates,
state transitions, credential files, and retrieval checks execute unchanged.
Sockets and subprocess creation are prohibited, even on unexpected code paths.
Native recall, query auditing, and workflow execution need separate live tests.
"""

import copy
import importlib.util
import io
import json
import stat
import sys
import tempfile
import unittest
import urllib.error
import uuid
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True


def forbid_external_io(event, args):
    if event.startswith("socket.") or event in {"subprocess.Popen", "os.system"}:
        raise AssertionError(
            "External network/process access is forbidden in knowledge tests"
        )


sys.addaudithook(forbid_external_io)
SPEC = importlib.util.spec_from_file_location(
    "kaogong_knowledge_test", ROOT / "scripts/dify_kaogong_knowledge.py"
)
KNOWLEDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(KNOWLEDGE)
METHODS = json.loads((ROOT / "conf/dify-kaogong/methods.json").read_text())["methods"]
METHODS_BEFORE = copy.deepcopy(METHODS)


class FakeServer:
    """Synthetic native-shaped API, with global rank before metadata filtering."""

    def __init__(self):
        self.base = "http://127.0.0.1:5001"
        self.tenant = str(uuid.uuid4())
        self.secret = "dataset-" + uuid.uuid4().hex
        self.key_id = str(uuid.uuid4())
        self.keys = []
        self.datasets = {}
        self.calls = []
        self.protocol_errors = []
        self.last_saved = None
        self.fail_after = None
        self.bad = None

    def require(self, condition, message):
        # Importer's safe exception wrapper suppresses AssertionError details;
        # preserve protocol failures so negative tests cannot pass accidentally.
        if not condition:
            self.protocol_errors.append(message)
            raise AssertionError(message)

    def trip(self, phase):
        if self.fail_after == phase:
            self.fail_after = None
            raise KNOWLEDGE._Error("Synthetic ambiguous create after server commit")

    def saved_generation(self, dataset_id):
        marker = self.datasets[dataset_id]["detail"]["description"]
        return next(
            generation
            for generation in self.last_saved["knowledge"]["generations"].values()
            if generation["marker"] == marker
        )

    def api(self, method, path, data=None):
        if path == "/workspaces/current/summary":
            self.calls.append((method, path, copy.deepcopy(data)))
            return {"id": self.tenant, "role": "owner"}
        if path == "/datasets/api-keys":
            self.calls.append((method, path, copy.deepcopy(data)))
            if method == "GET":
                return {"data": copy.deepcopy(self.keys)}
            self.require(method == "POST", "Unexpected key mutation")
            self.require(
                self.last_saved["knowledge"]["key_intent"]["phase"] == "creating",
                "Key creation intent was not durable before POST",
            )
            self.require(
                data == {"dataset_ids": [], "knowledge_space_ids": []},
                "Wrong key scope",
            )
            self.keys.append(
                {
                    "id": self.key_id,
                    "type": "dataset",
                    "token": self.secret[:5] + "..." + self.secret[-4:],
                    "dataset_ids": [],
                    "knowledge_space_ids": [],
                }
            )
            self.trip("key")
            return {**self.keys[0], "token": self.secret}
        return self.call(method, path, data)

    def call(self, method, path, data=None, **kwargs):
        route = path.split("?")[0]
        self.calls.append((method, route, copy.deepcopy(data)))
        parts = route.strip("/").split("/")
        self.require(parts[0] == "datasets", "Non-dataset service route")
        if len(parts) == 1:
            if method == "GET":
                return {
                    "data": [
                        copy.deepcopy(d["detail"]) for d in self.datasets.values()
                    ],
                    "has_more": False,
                }
            self.require(method == "POST", "Unexpected dataset mutation")
            generations = self.last_saved["knowledge"]["generations"].values()
            self.require(
                any(
                    g["marker"] == data["description"] and g["phase"] == "creating"
                    for g in generations
                ),
                "Dataset creation intent was not durable before POST",
            )
            dataset_id = str(uuid.uuid4())
            detail = {
                **copy.deepcopy(data),
                "id": dataset_id,
                "retrieval_model_dict": copy.deepcopy(data["retrieval_model"]),
                "enable_api": True,
                "is_multimodal": False,
                "embedding_available": True,
            }
            self.datasets[dataset_id] = {"detail": detail, "fields": [], "docs": {}}
            self.trip("dataset")
            return copy.deepcopy(detail)
        dataset = self.datasets[parts[1]]
        if len(parts) == 2:
            self.require(method == "GET", "Existing dataset was mutated")
            return copy.deepcopy(dataset["detail"])
        if parts[2:] == ["metadata"]:
            if method == "GET":
                return {"doc_metadata": copy.deepcopy(dataset["fields"])}
            generation = self.saved_generation(parts[1])
            self.require(
                generation["metadata"][data["name"]]["phase"] == "creating",
                "Metadata creation intent was not durable before POST",
            )
            field = {**data, "id": str(uuid.uuid4())}
            dataset["fields"].append(field)
            self.trip("field")
            return copy.deepcopy(field)
        if parts[2:] == ["document", "create-by-text"]:
            generation = self.saved_generation(parts[1])
            self.require(
                any(
                    e["name"] == data["name"] and e["phase"] == "creating"
                    for e in generation["documents"].values()
                ),
                "Document creation intent was not durable before POST",
            )
            self.require(data["doc_form"] == "text_model", "Wrong document format")
            rules = data["process_rule"]["rules"]
            self.require(
                rules["pre_processing_rules"] == [], "Method text preprocessing enabled"
            )
            self.require(
                rules["segmentation"]["chunk_overlap"] == 0, "Overlapping method chunks"
            )
            self.require(
                len(data["text"]) <= rules["segmentation"]["max_tokens"],
                "Method would be split",
            )
            document_id, segment_id = str(uuid.uuid4()), str(uuid.uuid4())
            detail = {
                "id": document_id,
                "name": data["name"],
                "enabled": True,
                "archived": False,
                "indexing_status": "completed",
                "doc_metadata": [],
                "error": None,
            }
            segment = {
                "id": segment_id,
                "document_id": document_id,
                "content": data["text"],
                "status": "completed",
                "enabled": True,
                "keywords": ["native-default"],
            }
            dataset["docs"][document_id] = {"detail": detail, "segment": segment}
            self.trip("document")
            return {"document": copy.deepcopy(detail), "batch": "synthetic-index-batch"}
        if parts[2:] == ["documents"]:
            return {
                "data": [copy.deepcopy(v["detail"]) for v in dataset["docs"].values()],
                "has_more": False,
            }
        if parts[2:] == ["documents", "metadata"]:
            for operation in data["operation_data"]:
                self.require(
                    operation["partial_update"] is True,
                    "Metadata replaced rather than partially mapped",
                )
                dataset["docs"][operation["document_id"]]["detail"]["doc_metadata"] = [
                    {**field, "type": "string"} for field in operation["metadata_list"]
                ]
            self.trip("mapping")
            return {"result": "success"}
        if parts[2] == "documents":
            document = dataset["docs"][parts[3]]
            if len(parts) == 4:
                result = copy.deepcopy(document["detail"])
                if self.bad == "index":
                    result["indexing_status"] = "error"
                if self.bad == "waiting":
                    result["indexing_status"] = "indexing"
                return result
            if len(parts) == 6 and parts[4] == "segments":
                self.require(method == "POST", "Unexpected single-segment route")
                self.require(
                    parts[5] == document["segment"]["id"], "Wrong segment update ID"
                )
                self.require(
                    set(data) == {"segment"} and set(data["segment"]) == {"keywords"},
                    "Keyword update overwrote content or other segment fields",
                )
                generation = self.saved_generation(parts[1])
                entry = next(
                    e
                    for e in generation["documents"].values()
                    if e["document_id"] == parts[3]
                )
                intent = entry["keyword_intent"]
                self.require(
                    intent["phase"] == "updating",
                    "Keyword intent not durable before POST",
                )
                self.require(
                    data["segment"]["keywords"] == intent["desired"],
                    "Posted keywords differ from saved intent",
                )
                self.require(
                    document["segment"]["keywords"] == intent["before"],
                    "Keyword update did not reconcile original values",
                )
                self.trip("keywords-before")
                document["segment"]["keywords"] = copy.deepcopy(
                    data["segment"]["keywords"]
                )
                if self.bad == "keyword-content":
                    document["segment"]["content"] = (
                        "Synthetic content changed during native keyword update"
                    )
                if self.bad == "keyword-index":
                    document["segment"].update(
                        status="error", error="Synthetic indexing failure"
                    )
                if self.bad == "keyword-wait":
                    document["remaining_index_polls"] = 1
                self.trip("keywords")
                return {
                    "data": copy.deepcopy(document["segment"]),
                    "doc_form": "text_model",
                }
            self.require(parts[4:] == ["segments"], "Unexpected document route")
            segments = [copy.deepcopy(document["segment"])]
            if document.get("remaining_index_polls", 0):
                document["remaining_index_polls"] -= 1
                segments[0]["status"] = "indexing"
            if self.bad == "split":
                segments.append({**segments[0], "id": str(uuid.uuid4())})
            if self.bad == "content":
                segments[0]["content"] = "Synthetic server-side content drift"
            return {"data": segments, "has_more": False}
        if parts[2:] == ["retrieve"]:
            self.require(
                "metadata_filtering_conditions" not in data,
                "Filters put at ignored request root",
            )
            retrieval = data["retrieval_model"]
            filters = retrieval["metadata_filtering_conditions"]
            self.require(
                filters["logical_operator"] == "and",
                "Metadata filters are not conjunctive",
            )
            self.require(
                {c["name"] for c in filters["conditions"]} == {"teacher_id", "status"},
                "Missing hard filter",
            )
            self.require(
                all(c["comparison_operator"] == "is" for c in filters["conditions"]),
                "Wrong filter comparison",
            )
            self.require(
                retrieval["top_k"] >= len(dataset["docs"]),
                "Global Top-K can starve a teacher",
            )
            records = []
            globally_ranked = list(dataset["docs"].values())[: retrieval["top_k"]]
            for document in globally_ranked:
                metadata = {
                    v["name"]: v["value"] for v in document["detail"]["doc_metadata"]
                }
                accepted = all(
                    metadata.get(c["name"]) == c["value"]
                    for c in filters["conditions"]
                    if c["name"] != self.bad
                )
                if self.bad == "filter":
                    accepted = True
                # Reproduce the reported lexical gap without pretending to run
                # Jieba: example-specific terms must exist in the stored index.
                query_terms = [
                    word
                    for word in ("\u62a5\u4fee", "\u501f\u8fd8")
                    if word in data["query"]
                ]
                if (
                    dataset["detail"]["indexing_technique"] == "economy"
                    and query_terms
                    and not any(
                        word in document["segment"]["keywords"] for word in query_terms
                    )
                ):
                    accepted = False
                if accepted and self.bad != "recall":
                    records.append(
                        {
                            "segment": {
                                **copy.deepcopy(document["segment"]),
                                "document": {
                                    **copy.deepcopy(document["detail"]),
                                    "doc_metadata": metadata,
                                },
                            }
                        }
                    )
            return {"query": {"content": data["query"]}, "records": records}
        self.require(False, "Unexpected synthetic API route")


class ImporterTests(unittest.TestCase):
    def setUp(self):
        self.server = FakeServer()
        self.state = {
            "tenant_id": self.server.tenant,
            "origin": self.server.base,
            "app_id": "untouched",
        }
        self.saved = []
        self.mock = patch.object(
            KNOWLEDGE, "_Api", lambda base, token: self.server.call
        )
        self.mock.start()
        self.addCleanup(self.mock.stop)
        self.fail_key_save = False

    def tearDown(self):
        self.assertEqual(self.server.protocol_errors, [])
        self.assertEqual(METHODS, METHODS_BEFORE, "Reviewed source cards were mutated")

    def save(self, state):
        self.assertTrue(
            self.server.secret not in json.dumps(state),
            "Credential entered persisted state",
        )
        if (
            self.fail_key_save
            and state["knowledge"].get("key_intent", {}).get("phase") == "created"
        ):
            self.fail_key_save = False
            raise OSError("Synthetic failure after key file fsync")
        self.saved.append(copy.deepcopy(state))
        self.server.last_saved = copy.deepcopy(state)

    def apply(self, methods=None, **kwargs):
        return KNOWLEDGE.ensure_knowledge(
            self.server,
            self.server.tenant,
            copy.deepcopy(METHODS if methods is None else methods),
            self.state,
            self.save,
            **kwargs,
        )

    def writes(self):
        return [
            (m, p)
            for m, p, _ in self.server.calls
            if m != "GET" and not p.endswith("/retrieve")
        ]

    def restore(self):
        self.state = copy.deepcopy(self.saved[-1])
        if hasattr(self.server, "_kaogong_knowledge_token"):
            del self.server._kaogong_knowledge_token

    def test_repeat_apply_and_no_credential_leak(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            first = self.apply()
            writes = self.writes()
            second = self.apply()
        self.assertEqual(first, second)
        self.assertEqual(self.writes(), writes)
        self.assertEqual(len(first["documents"]), len(METHODS))
        self.assertEqual(first["retrieval_top_k"], len(METHODS))
        self.assertEqual(self.state["app_id"], "untouched")
        self.assertEqual(self.state["knowledge"]["history"], [])
        self.assertTrue(
            self.server.secret
            not in json.dumps(first) + stdout.getvalue() + stderr.getvalue()
        )
        self.assertTrue(first["verification"]["passed"])
        self.assertFalse(first["verification"]["native_node_execution_tested"])

    def test_changed_generation_preserves_old(self):
        self.assertGreater(len(METHODS), 1, "Test requires at least two reviewed cards")
        old = self.apply()
        snapshot = copy.deepcopy(self.server.datasets[old["dataset_id"]])
        new = self.apply(METHODS[:-1])
        self.assertNotEqual(old["dataset_id"], new["dataset_id"])
        self.assertEqual(snapshot, self.server.datasets[old["dataset_id"]])
        self.assertEqual(self.state["knowledge"]["history"], [old])
        self.assertEqual(len(self.server.keys), 1)

    def test_committed_create_recovers_from_durable_intent(self):
        for phase in ("dataset", "field", "document", "mapping"):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as directory:
                self.server = FakeServer()
                self.state = {
                    "tenant_id": self.server.tenant,
                    "origin": self.server.base,
                }
                key_file = Path(directory) / "key"
                self.server.fail_after = phase
                with self.assertRaisesRegex(RuntimeError, "Synthetic ambiguous"):
                    self.apply(token_file=key_file)
                self.restore()
                result = self.apply(token_file=key_file)
                self.assertTrue(result["verification"]["passed"])
                self.assertEqual(len(self.server.datasets), 1)
                self.assertEqual(len(self.server.keys), 1)
                dataset = next(iter(self.server.datasets.values()))
                self.assertEqual(len(dataset["docs"]), len(METHODS))
                self.assertEqual(len(dataset["fields"]), 5)
                self.assertEqual(self.server.protocol_errors, [])

    def test_absent_create_result_is_not_reposted(self):
        self.server.fail_after = "dataset"
        with self.assertRaises(RuntimeError):
            self.apply()
        self.server.datasets.clear()
        writes = self.writes()
        with self.assertRaisesRegex(RuntimeError, "no unique UUID marker"):
            self.apply()
        self.assertEqual(self.writes(), writes)

    def test_nonunique_create_marker_is_not_adopted(self):
        self.server.fail_after = "dataset"
        with self.assertRaises(RuntimeError):
            self.apply()
        duplicate = copy.deepcopy(next(iter(self.server.datasets.values())))
        duplicate["detail"]["id"] = str(uuid.uuid4())
        self.server.datasets[duplicate["detail"]["id"]] = duplicate
        writes = self.writes()
        with self.assertRaisesRegex(RuntimeError, "no unique UUID marker"):
            self.apply()
        self.assertEqual(self.writes(), writes)

    def test_lost_reveal_once_key_is_not_recreated(self):
        self.server.fail_after = "key"
        with self.assertRaises(RuntimeError):
            self.apply()
        with self.assertRaisesRegex(RuntimeError, "already attempted"):
            self.apply()
        self.assertEqual(len(self.server.keys), 1)
        self.assertEqual(len(self.server.datasets), 0)

    def test_key_file_recovers_after_state_save_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            key_file = Path(directory) / "key"
            self.fail_key_save = True
            with self.assertRaises(RuntimeError):
                self.apply(token_file=key_file)
            self.assertTrue(key_file.exists())
            self.restore()
            self.assertEqual(self.state["knowledge"]["key_intent"]["phase"], "creating")
            self.apply(token_file=key_file)
            self.assertEqual(self.state["knowledge"]["key_intent"]["phase"], "created")
            self.assertEqual(len(self.server.keys), 1)

    def test_missing_key_file_cannot_use_cached_key_or_mint_another(self):
        with tempfile.TemporaryDirectory() as directory:
            key_file = Path(directory) / "key"
            self.apply(token_file=key_file)
            key_file.unlink()
            writes = self.writes()
            with self.assertRaisesRegex(RuntimeError, "already attempted"):
                self.apply(token_file=key_file)
            self.assertEqual(self.writes(), writes)
            self.assertEqual(len(self.server.keys), 1)

    def test_bad_recall_preserves_current(self):
        old = self.apply()
        self.server.bad = "recall"
        with self.assertRaisesRegex(RuntimeError, "recall returned no evidence"):
            self.apply(METHODS[:-1])
        self.assertEqual(self.state["knowledge"]["current"], old)

    def test_filters_fail_independently(self):
        for ignored_filter in ("teacher_id", "status", "filter"):
            with self.subTest(ignored_filter=ignored_filter):
                self.server = FakeServer()
                self.state = {
                    "tenant_id": self.server.tenant,
                    "origin": self.server.base,
                }
                self.server.bad = ignored_filter
                with self.assertRaisesRegex(
                    RuntimeError, "filtering failed|mixed teachers"
                ):
                    self.apply()
                self.assertIsNone(self.state["knowledge"]["current"])
                self.assertEqual(self.server.protocol_errors, [])

    def test_all_segments_top_k_and_positive_negative_probes(self):
        result = self.apply()
        probes = [
            data
            for method, path, data in self.server.calls
            if method == "POST" and path.endswith("/retrieve")
        ]
        query_count = sum(len({m["name"], m["examples"][0]["input"]}) for m in METHODS)
        self.assertEqual(len(probes), query_count * 3)
        positive = wrong_teacher = wrong_status = 0
        for payload in probes:
            retrieval = payload["retrieval_model"]
            self.assertEqual(retrieval["top_k"], len(result["documents"]))
            values = {
                c["name"]: c["value"]
                for c in retrieval["metadata_filtering_conditions"]["conditions"]
            }
            if values["status"] == "quarantined":
                wrong_status += 1
            elif values["teacher_id"].startswith("not-a-teacher-"):
                wrong_teacher += 1
            else:
                positive += 1
        self.assertEqual((positive, wrong_teacher, wrong_status), (query_count,) * 3)

    def test_index_failure_split_and_content_drift(self):
        for bad in ("index", "split", "content"):
            with self.subTest(bad=bad):
                self.server = FakeServer()
                self.state = {
                    "tenant_id": self.server.tenant,
                    "origin": self.server.base,
                }
                self.server.bad = bad
                with self.assertRaisesRegex(
                    RuntimeError, "indexing failed|one full segment|segment content"
                ):
                    self.apply()
                self.assertIsNone(self.state["knowledge"]["current"])
                self.assertEqual(self.server.protocol_errors, [])

    def test_indexing_deadline(self):
        self.server.bad = "waiting"
        with (
            patch.object(KNOWLEDGE.time, "sleep"),
            patch.object(KNOWLEDGE.time, "monotonic", side_effect=[0, 2]),
            self.assertRaisesRegex(RuntimeError, "timed out"),
        ):
            self.apply(index_timeout=1)

    def test_document_metadata_drift_is_not_overwritten(self):
        result = self.apply()
        dataset = self.server.datasets[result["dataset_id"]]
        document = next(iter(dataset["docs"].values()))
        document["detail"]["doc_metadata"][0]["value"] = "different-teacher"
        writes = self.writes()
        with self.assertRaisesRegex(RuntimeError, "metadata value or ID mismatch"):
            self.apply()
        self.assertEqual(self.writes(), writes)

    def test_native_metadata_ids_and_types_are_read_back(self):
        result = self.apply()
        dataset = self.server.datasets[result["dataset_id"]]
        self.assertEqual(
            result["metadata"], {f["name"]: f["id"] for f in dataset["fields"]}
        )
        writes = self.writes()
        for field, replacement in (("id", str(uuid.uuid4())), ("type", "number")):
            with self.subTest(field=field):
                original = dataset["fields"][0][field]
                dataset["fields"][0][field] = replacement
                with self.assertRaisesRegex(
                    RuntimeError, "metadata identity or type changed"
                ):
                    self.apply()
                self.assertEqual(self.writes(), writes)
                dataset["fields"][0][field] = original

    def test_protected_key_file_permissions_and_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            key_file = Path(directory) / "key"
            self.apply(token_file=key_file)
            self.assertEqual(stat.S_IMODE(key_file.stat().st_mode), 0o600)
            self.restore()
            self.apply(token_file=key_file)
            self.assertEqual(len(self.server.keys), 1)
            key_file.chmod(0o644)
            with self.assertRaisesRegex(RuntimeError, "mode 0600"):
                self.apply(token_file=key_file)

    def test_key_file_symlink_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            key_file = Path(directory) / "key"
            KNOWLEDGE._write_key(key_file, self.server.secret)
            link = Path(directory) / "link"
            link.symlink_to(key_file)
            with self.assertRaises(RuntimeError):
                self.apply(token_file=link)
            self.assertEqual(self.server.keys, [])

    def test_empty_and_fixture_cards_are_rejected_before_io(self):
        with self.assertRaisesRegex(RuntimeError, "no empty or fixture"):
            self.apply([])
        invalid = copy.deepcopy(METHODS[0])
        invalid["teacher_id"] = "fixture-teacher"
        invalid["content_hash"] = KNOWLEDGE._digest(
            {k: v for k, v in invalid.items() if k != "content_hash"}
        )
        with self.assertRaisesRegex(RuntimeError, "fixtures must never enter"):
            self.apply([invalid])
        self.assertEqual(self.server.calls, [])

    def test_wrong_tenant_and_hash_are_rejected_without_writes(self):
        self.state["tenant_id"] = str(uuid.uuid4())
        with self.assertRaisesRegex(RuntimeError, "different tenant or origin"):
            self.apply()
        invalid = copy.deepcopy(METHODS[0])
        invalid["content_hash"] = "0" * 64
        with self.assertRaisesRegex(RuntimeError, "hash mismatch"):
            self.apply([invalid])
        self.assertEqual(self.writes(), [])

    def test_high_quality_requires_explicit_verified_configuration(self):
        with self.assertRaisesRegex(RuntimeError, "explicitly verified"):
            self.apply(
                embedding={
                    "provider": "native-test-provider",
                    "model": "test-embedding",
                }
            )
        result = self.apply(
            embedding={
                "provider": "native-test-provider",
                "model": "test-embedding",
                "verified": True,
            }
        )
        self.assertEqual(result["indexing_technique"], "high_quality")
        self.assertEqual(result["retrieval_model"]["search_method"], "semantic_search")

    def test_verify_cannot_provision_missing_credential(self):
        result = self.apply()
        self.restore()
        writes = self.writes()
        with self.assertRaisesRegex(RuntimeError, "requires its dedicated API key"):
            KNOWLEDGE.verify_retrieval(
                self.server, self.server.tenant, result, copy.deepcopy(METHODS)
            )
        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(RuntimeError, "verification cannot provision keys"),
        ):
            KNOWLEDGE.verify_retrieval(
                self.server,
                self.server.tenant,
                result,
                copy.deepcopy(METHODS),
                token_file=Path(directory) / "missing",
            )
        self.assertEqual(self.writes(), writes)
        self.assertEqual(len(self.server.keys), 1)

    def test_verify_changes_no_resources_or_shared_state(self):
        result = self.apply()
        state = copy.deepcopy(self.state)
        resources = copy.deepcopy(self.server.datasets)
        writes = self.writes()
        checked = KNOWLEDGE.verify_retrieval(
            self.server, self.server.tenant, result, copy.deepcopy(METHODS)
        )
        self.assertTrue(checked["passed"])
        self.assertEqual(self.state, state)
        self.assertEqual(self.server.datasets, resources)
        self.assertEqual(self.writes(), writes)

    def test_teaching_keyword_strategy_is_deterministic_and_bounded(self):
        method = copy.deepcopy(METHODS[0])
        expected = KNOWLEDGE._teaching_keywords(method)
        self.assertEqual(expected, sorted(set(expected)))
        self.assertLessEqual(len(expected), 4096)
        method["audit"] = {"unindexed": "AuditOnlySentinel"}
        method["sources"] = [{"quote": "ProvenanceOnlySentinel"}]
        method["examples"][0]["output"] = "AnswerOnlySentinel"
        self.assertEqual(KNOWLEDGE._teaching_keywords(method), expected)
        sample = {
            "name": "ABC",
            "steps": ["\u7532\u4e59\u4e19\u4e01\u620a\u5df1\u5e9a"],
            "examples": [{"input": "repair42"}],
        }
        terms = KNOWLEDGE._teaching_keywords(sample)
        self.assertIn("ABC", terms)
        self.assertIn("abc", terms)
        self.assertIn("repair42", terms)
        for length in range(2, 7):
            self.assertIn(sample["steps"][0][:length], terms)
        self.assertNotIn(sample["steps"][0], terms)
        for invalid in (["x"] * 4097, ["x" * 129]):
            with (
                self.subTest(size=len(invalid)),
                self.assertRaisesRegex(RuntimeError, "no truncation"),
            ):
                KNOWLEDGE._keyword_values(invalid)
        with (
            patch.object(KNOWLEDGE, "_MAX_KEYWORDS", 2),
            self.assertRaisesRegex(RuntimeError, "no truncation"),
        ):
            self.apply()
        self.assertEqual(self.writes(), [])

    def test_keyword_updates_preserve_original_terms_and_complete_cards(self):
        result = self.apply()
        self.assertEqual(result["keyword_strategy"], KNOWLEDGE._KEYWORD_STRATEGY)
        dataset = self.server.datasets[result["dataset_id"]]
        calls = [
            payload
            for method, path, payload in self.server.calls
            if method == "POST" and "/segments/" in path
        ]
        self.assertEqual(len(calls), len(METHODS))
        for method in METHODS:
            entry = result["documents"][method["skill_id"]]
            intent = entry["keyword_intent"]
            segment = dataset["docs"][entry["document_id"]]["segment"]
            self.assertEqual(intent["before"], ["native-default"])
            self.assertEqual(intent["phase"], "indexed")
            self.assertEqual(intent["content_hash"], method["content_hash"])
            self.assertEqual(segment["content"], KNOWLEDGE._canonical(method))
            self.assertEqual(segment["keywords"], intent["desired"])
            self.assertTrue(
                set(KNOWLEDGE._teaching_keywords(method)) <= set(segment["keywords"])
            )
            self.assertIn("native-default", segment["keywords"])
        for payload in calls:
            self.assertEqual(set(payload["segment"]), {"keywords"})

    def test_existing_pending_generation_is_enriched_without_duplicate_creation(self):
        result = self.apply()
        generation = next(iter(self.state["knowledge"]["generations"].values()))
        # Seed the exact earlier persisted schema: imported docs ready, recall
        # not accepted, no keyword intents/strategy and no current graph mapping.
        generation.pop("keyword_strategy")
        generation["phase"] = "created"
        self.state["knowledge"]["current"] = None
        for entry in generation["documents"].values():
            original = entry.pop("keyword_intent")["before"]
            self.server.datasets[result["dataset_id"]]["docs"][entry["document_id"]][
                "segment"
            ]["keywords"] = original
        self.save(self.state)
        example = next(m for m in METHODS if m["teacher_id"] == "li-mengyuan")
        probe = {
            "query": example["examples"][0]["input"],
            "retrieval_model": {
                **result["retrieval_model"],
                "metadata_filtering_conditions": {
                    "logical_operator": "and",
                    "conditions": [
                        {
                            "name": "teacher_id",
                            "comparison_operator": "is",
                            "value": example["teacher_id"],
                        },
                        {
                            "name": "status",
                            "comparison_operator": "is",
                            "value": "approved",
                        },
                    ],
                },
            },
        }
        route = "/datasets/" + result["dataset_id"] + "/retrieve"
        self.assertEqual(self.server.call("POST", route, probe)["records"], [])
        count = len(self.writes())
        upgraded = self.apply()
        self.assertEqual(upgraded["dataset_id"], result["dataset_id"])
        self.assertEqual(
            {e["document_id"] for e in upgraded["documents"].values()},
            {e["document_id"] for e in result["documents"].values()},
        )
        self.assertTrue(all("/segments/" in path for _, path in self.writes()[count:]))
        self.assertTrue(upgraded["verification"]["passed"])
        self.assertTrue(self.server.call("POST", route, probe)["records"])

    def test_keyword_timeout_reconciles_before_or_desired_without_blind_retry(self):
        for phase in ("keywords", "keywords-before"):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as directory:
                self.server = FakeServer()
                self.state = {
                    "tenant_id": self.server.tenant,
                    "origin": self.server.base,
                }
                self.server.fail_after = phase
                key = Path(directory) / "key"
                with self.assertRaisesRegex(RuntimeError, "Synthetic ambiguous"):
                    self.apply(token_file=key)
                posts = [
                    path
                    for method, path, _ in self.server.calls
                    if method == "POST" and "/segments/" in path
                ]
                self.assertEqual(len(posts), 1)
                self.restore()
                result = self.apply(token_file=key)
                repeats = sum(
                    method == "POST" and path == posts[0]
                    for method, path, _ in self.server.calls
                )
                self.assertEqual(repeats, 1 if phase == "keywords" else 2)
                self.assertEqual(len(self.server.datasets), 1)
                self.assertTrue(result["verification"]["passed"])
                self.assertEqual(self.server.protocol_errors, [])

    def test_pending_keyword_drift_is_not_overwritten(self):
        self.server.fail_after = "keywords-before"
        with self.assertRaises(RuntimeError):
            self.apply()
        segment = next(
            iter(next(iter(self.server.datasets.values()))["docs"].values())
        )["segment"]
        segment["keywords"].append("manual-user-change")
        writes = self.writes()
        with self.assertRaisesRegex(RuntimeError, "keywords changed outside"):
            self.apply()
        self.assertEqual(self.writes(), writes)
        self.assertIsNone(self.state["knowledge"]["current"])

    def test_accepted_keyword_drift_and_strategy_changes_are_not_overwritten(self):
        result = self.apply()
        segment = next(
            iter(self.server.datasets[result["dataset_id"]]["docs"].values())
        )["segment"]
        segment["keywords"].append("manual-user-change")
        writes = self.writes()
        with self.assertRaisesRegex(RuntimeError, "keywords changed"):
            self.apply()
        with self.assertRaisesRegex(RuntimeError, "keyword readback differs"):
            KNOWLEDGE.verify_retrieval(
                self.server, self.server.tenant, result, copy.deepcopy(METHODS)
            )
        self.assertEqual(self.writes(), writes)
        generation = next(iter(self.state["knowledge"]["generations"].values()))
        generation["keyword_strategy"] = "different-strategy"
        with self.assertRaisesRegex(
            RuntimeError, "different immutable keyword strategy"
        ):
            self.apply()
        self.assertEqual(self.writes(), writes)

    def test_keyword_update_rechecks_full_content_and_index_status(self):
        for bad in ("keyword-content", "keyword-index"):
            with self.subTest(bad=bad):
                self.server = FakeServer()
                self.state = {
                    "tenant_id": self.server.tenant,
                    "origin": self.server.base,
                }
                self.server.bad = bad
                with self.assertRaisesRegex(RuntimeError, "segment content"):
                    self.apply()
                self.assertIsNone(self.state["knowledge"]["current"])
                self.assertEqual(self.server.protocol_errors, [])

    def test_keyword_index_completion_is_waited_for(self):
        self.server.bad = "keyword-wait"
        with patch.object(KNOWLEDGE.time, "sleep") as sleep:
            result = self.apply()
        self.assertTrue(result["verification"]["passed"])
        self.assertEqual(sleep.call_count, len(METHODS))


class FakeOpener:
    def __init__(self, fail=None):
        self.calls = []
        self.fail = fail

    def open(self, request, timeout):
        self.calls.append(request)
        if self.fail:
            raise self.fail(request)
        return io.BytesIO(b"{}")


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.api = KNOWLEDGE._Api(
            "http://127.0.0.1:5001", "dataset-" + uuid.uuid4().hex
        )

    def test_public_route_and_no_console_credentials(self):
        opener = FakeOpener()
        self.api.opener = opener
        self.api("GET", "/datasets")
        request = opener.calls[0]
        self.assertEqual(request.full_url, "http://127.0.0.1:5001/v1/datasets")
        headers = {k.lower(): v for k, v in request.header_items()}
        self.assertNotIn("cookie", headers)
        self.assertNotIn("x-csrf-token", headers)
        self.assertTrue(headers["authorization"].startswith("Bearer dataset-"))

    def test_write_errors_are_not_retried_or_disclosed(self):
        for status in (401, 403, 429, 500, 503):
            with self.subTest(status=status):
                opener = FakeOpener(
                    lambda req, status=status: urllib.error.HTTPError(
                        req.full_url,
                        status,
                        "synthetic-sensitive-message",
                        {},
                        io.BytesIO(b"synthetic-sensitive-body"),
                    )
                )
                self.api.opener = opener
                with self.assertRaises(RuntimeError) as raised:
                    self.api("POST", "/datasets", {"name": "synthetic-test"})
                self.assertEqual(len(opener.calls), 1)
                self.assertNotIn("sensitive", str(raised.exception))
                self.assertTrue(self.api.token not in str(raised.exception))

    def test_get_retries_are_bounded(self):
        opener = FakeOpener(
            lambda req: urllib.error.HTTPError(
                req.full_url, 429, "hidden", {}, io.BytesIO(b"hidden")
            )
        )
        self.api.opener = opener
        with (
            patch.object(KNOWLEDGE.time, "sleep") as sleep,
            self.assertRaises(RuntimeError),
        ):
            self.api("GET", "/datasets")
        self.assertEqual(len(opener.calls), 3)
        self.assertEqual([c.args for c in sleep.call_args_list], [(1,), (2,)])

    def test_get_auth_errors_are_not_retried(self):
        for status in (401, 403):
            with self.subTest(status=status):
                opener = FakeOpener(
                    lambda req, status=status: urllib.error.HTTPError(
                        req.full_url, status, "hidden", {}, io.BytesIO(b"hidden")
                    )
                )
                self.api.opener = opener
                with self.assertRaises(RuntimeError):
                    self.api("GET", "/datasets")
                self.assertEqual(len(opener.calls), 1)

    def test_redirects_are_refused(self):
        with self.assertRaisesRegex(RuntimeError, "redirect refused"):
            KNOWLEDGE._NoRedirect().redirect_request(
                None, None, 302, "", {}, "https://invalid.local/"
            )

    def test_expired_deadline_prevents_io(self):
        opener = FakeOpener()
        self.api.opener = opener
        with self.assertRaisesRegex(RuntimeError, "deadline exceeded"):
            self.api("GET", "/datasets", deadline=0)
        self.assertEqual(opener.calls, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
