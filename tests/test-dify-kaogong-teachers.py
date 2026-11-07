"""Offline native-graph and teacher-helper contracts, not live model acceptance.

Method cards, exact quotations and hashes are the real reviewed assets. Retrieval
envelopes follow the installed native Source shape, but are local fixtures, not a
claim that retrieval ran. Classifications, solutions and reviews are explicitly
synthetic model outputs. Python calls individual Code helpers only; it neither
implements nor tests Dify's parallel Iteration scheduler. The companion base
suite installs socket/command guards before any application runtime is loaded.
"""

import copy
import importlib.util
import itertools
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "kaogong_base_test_fixtures", ROOT / "tests/test-dify-kaogong.py"
)
BASE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(BASE)
ASSETS = BASE.ASSETS
REAL_DATA = BASE.REAL_DATA
NODES = BASE.NODES
WORKFLOW = BASE.WORKFLOW
SOURCE = (
    (ASSETS / "nodes.py").read_text() + "\n" + (ASSETS / "teacher_nodes.py").read_text()
)
METHODS = {method["skill_id"]: method for method in REAL_DATA["methods"]["methods"]}
SUMMARY_IDS = ["li-mengyuan", "yuan-dong"]
SUMMARY_SKILLS = ["li-mengyuan.keyword-extraction", "yuan-dong.summary-headings"]
SUMMARY_QUESTION = METHODS[SUMMARY_SKILLS[0]]["examples"][0]["input"]
GROWTH_QUESTION = "\u73b0\u671f\u91cf5000\u4e07\u5143\uff0c\u589e\u957f\u738712.5%\uff0c\u6c42\u57fa\u671f\u91cf\u548c\u589e\u957f\u91cf\u3002"
SUMMARY_ANSWERS = [
    "\u8fdb\u5ea6\u53cd\u9988\u7f3a\u5931\uff0c\u767b\u8bb0\u91cd\u590d\uff0c\u591c\u95f4\u63a5\u542c\u670d\u52a1\u7f3a\u4f4d\u3002",
    "\u4e00\u662f\u53cd\u9988\u7f3a\u5931\uff0c\u767b\u8bb0\u540e\u4e0d\u544a\u77e5\u8fdb\u5ea6\u3002\u4e8c\u662f\u767b\u8bb0\u91cd\u590d\u3002\u4e09\u662f\u591c\u95f4\u65e0\u4eba\u63a5\u542c\u7535\u8bdd\u3002",
]
MATERIAL_QUOTES = [
    "\u62a5\u4fee\u767b\u8bb0\u540e\u65e0\u4eba\u544a\u77e5\u529e\u7406\u8fdb\u5ea6\u3002",
    "\u70ed\u7ebf\u4e0e\u7f51\u7ad9\u91cd\u590d\u767b\u8bb0\u540c\u4e00\u4e8b\u9879\u3002",
    "\u591c\u95f4\u65e0\u4eba\u63a5\u542c\u62a5\u4fee\u7535\u8bdd\u3002",
]
BINDING = {
    **BASE.CLI.default_binding(REAL_DATA),
    "dataset_id": "00000000-0000-4000-8000-000000000900",
}


def dump(value):
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def classification(topics=None, *, complete=True):
    return dump(
        {
            "topic_ids": topics or ["shenlun.summary"],
            "complete": complete,
            "clarification": "" if complete else "\u7f3a\u5c11\u5fc5\u8981\u6750\u6599",
            "search_terms": "\u6750\u6599 \u65b9\u6cd5",
        }
    )


def review():
    """A synthetic all-true reviewer response, not independent semantic evidence."""
    return {
        "passed": True,
        "issues": [],
        "facts_supported": True,
        "method_applicable": True,
        "calculations_consistent": True,
        "word_limit_satisfied": True,
    }


def abstention(status="not_needed"):
    return {
        "status": status,
        "reason": "synthetic fixture",
        "skill_ids": [],
        "evidence": [],
        "conditions": [],
        "answer": "",
        "steps": [],
        "material_quotes": [],
        "calculations": [],
    }


def native_hit(card):
    """Native text_model content is raw complete JSON, never a title/QA wrapper."""
    return {
        "title": card["name"],
        "content": dump(card),
        "metadata": {
            "_source": "knowledge",
            "dataset_id": BINDING["dataset_id"],
            "document_id": "00000000-0000-4000-8000-000000001000",
            "segment_id": "00000000-0000-4000-8000-000000002000",
            "doc_metadata": {
                field: card[field]
                for field in (
                    "teacher_id",
                    "skill_id",
                    "topic_id",
                    "status",
                    "content_hash",
                )
            },
        },
    }


def summary_solution(index=0):
    """Synthetic answer applying a real card to its self-authored example."""
    card = METHODS[SUMMARY_SKILLS[index]]
    return {
        "status": "answered",
        "reason": "",
        "skill_ids": [card["skill_id"]],
        "evidence": [
            {"source_id": source["source_id"], "quote": source["quote"]}
            for source in card["sources"]
        ],
        "conditions": [
            {
                "skill_id": card["skill_id"],
                "condition_id": condition["condition_id"],
                "quote": SUMMARY_QUESTION,
            }
            for condition in card["applicable"]
        ],
        "answer": SUMMARY_ANSWERS[index],
        "steps": [
            "\u9010\u53e5\u6838\u5bf9\u6750\u6599\uff0c\u533a\u5206\u53cd\u9988\u3001\u767b\u8bb0\u548c\u63a5\u542c\u95ee\u9898\u3002"
        ],
        "material_quotes": list(MATERIAL_QUOTES),
        "calculations": [],
    }


def growth_solution():
    solution = abstention()
    operands = {"current": "5000", "rate": "12.5%", "unit": "\u4e07\u5143"}
    solution.update(
        status="answered",
        reason="",
        answer="\u57fa\u671f\u91cf4444.44\u4e07\u5143\uff0c\u589e\u957f\u91cf555.56\u4e07\u5143\u3002",
        steps=[
            "\u5148\u75315000\u9664\u4ee51.125\u6c42\u57fa\u671f\u91cf\uff0c\u518d\u7528\u73b0\u671f\u91cf\u51cf\u57fa\u671f\u91cf\u3002"
        ],
        material_quotes=[GROWTH_QUESTION],
        calculations=[
            {
                "operation": "growth_from_current",
                "operands": operands,
                "result": NODES.calculate("growth_from_current", operands),
            }
        ],
    )
    return solution


def arithmetic_record(operation, left, right, unit="", *, right_unit=None):
    operands = {
        "left": {"value": str(left), "unit": unit},
        "right": {
            "value": str(right),
            "unit": unit if right_unit is None else right_unit,
        },
    }
    return {
        "operation": operation,
        "operands": operands,
        "result": NODES.calculate(operation, operands),
    }


def arithmetic_solution(question, calculations, answer):
    solution = abstention("answered")
    solution.update(
        reason="",
        answer=answer,
        steps=["按原题数量顺序计算。"],
        material_quotes=[question],
        calculations=calculations,
    )
    return solution


def recruitment_fixture(capacities=(100, 80, 70, 50), threshold=70, *, unit=""):
    """Synthetic counterexample, never a replay of private live-run acceptance."""
    counts = "、".join(str(value) for value in capacities[:-1])
    counts += "和" + str(capacities[-1])
    question = (
        f"有{sum(capacities)}名求职者，四个专业分别有{counts}人。"
        f"至少多少人找到工作，才能保证有{threshold}名找到工作的人专业相同？"
    )
    worst = [min(value, threshold - 1) for value in capacities]
    total = worst[0]
    calculations = []
    for value in [*worst[1:], 1]:
        calculations.append(arithmetic_record("add", total, value, unit))
        total += value
    solution = abstention("answered")
    solution.update(
        reason="",
        answer=f"C. {total}人",
        steps=[
            f"最不利情形下，容量足够的专业各取{threshold - 1}人，其余全部取完。",
            f"此时共有{total - 1}人，再增加一人即可保证达到目标。",
        ],
        material_quotes=[question],
        calculations=calculations,
    )
    return question, solution, [arithmetic_record("subtract", threshold, 1, unit)]


class TeacherRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.original = copy.deepcopy(REAL_DATA)
        self.runtime = {"KAOGONG_CATALOG": copy.deepcopy(REAL_DATA)}
        exec(  # noqa: S102 - execute only the reviewed local runtime under I/O guards
            compile(SOURCE, "<trusted-combined-teacher-runtime>", "exec"), self.runtime
        )
        self.selected = self.select()

    def tearDown(self):
        self.assertEqual(REAL_DATA, self.original)
        self.assertEqual(self.runtime["KAOGONG_CATALOG"], self.original)

    def select(
        self, question=SUMMARY_QUESTION, *, state="", model_text=None, topics=None
    ):
        prepared = self.runtime["teacher_prepare"](question, state)
        return self.runtime["teacher_select"](
            classification(topics) if model_text is None else model_text,
            prepared["question"],
            prepared["request"],
            prepared["state"],
        )

    def evidence(self, index=0, *, hits=None, selected=None):
        return self.runtime["teacher_evidence"](
            SUMMARY_IDS[index],
            [native_hit(METHODS[SUMMARY_SKILLS[index]])] if hits is None else hits,
            (selected or self.selected)["context"],
        )["evidence"]

    def record(
        self,
        index=0,
        *,
        solution=None,
        checked_review=None,
        evidence=None,
        selected=None,
    ):
        return self.runtime["teacher_verify"](
            SUMMARY_IDS[index],
            dump(summary_solution(index)) if solution is None else solution,
            dump(review()) if checked_review is None else checked_review,
            self.evidence(index, selected=selected) if evidence is None else evidence,
            (selected or self.selected)["context"],
        )["result"]

    def render(self, records, *, selected=None, general=None, general_review=None):
        context = (selected or self.selected)["context"]
        serialized = self.runtime["teacher_serialize"](records, context)["results"]
        if general_review is None:
            checked = review()
            try:
                steps = json.loads(general)["steps"] if general else []
            except (ValueError, KeyError, TypeError):
                steps = []
            checked["reviewed_steps"] = steps
            general_review = dump(checked)
        return self.runtime["teacher_render"](
            context,
            serialized,
            dump(abstention()) if general is None else general,
            general_review,
        )

    def check_arithmetic(self, question, solution, *, prefix=None):
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        return self.runtime["_tn_check_answer"](
            solution,
            review(),
            None,
            "",
            json.loads(selected["context"]),
            self.runtime["_tn_catalog"](),
            calculation_prefix=prefix,
        )

    def test_both_real_summary_teachers_enumerated_independently(self):
        self.assertEqual(
            [t["teacher_id"] for t in self.selected["teachers"]], SUMMARY_IDS
        )
        self.assertEqual(
            [t["skill_ids"] for t in self.selected["teachers"]],
            [[key] for key in SUMMARY_SKILLS],
        )
        for index, teacher in enumerate(self.selected["teachers"]):
            self.assertEqual(
                self.runtime["teacher_extract"](teacher),
                {"teacher_id": SUMMARY_IDS[index]},
            )
        self.assertLessEqual(len(self.selected["teachers"]), 30)
        self.assertEqual(json.loads(self.selected["context"])["pending"], [])

    def test_native_hit_preserves_actual_card_content_and_hash(self):
        for index, key in enumerate(SUMMARY_SKILLS):
            hit = native_hit(METHODS[key])
            self.assertEqual(json.loads(hit["content"]), METHODS[key])
            self.assertEqual(
                NODES.method_content_hash(json.loads(hit["content"])),
                METHODS[key]["content_hash"],
            )
            envelope = json.loads(self.evidence(index, hits=[hit]))
            self.assertEqual(envelope["status"], "ok")
            self.assertEqual(envelope["methods"], [METHODS[key]])
            self.assertNotIn(SUMMARY_SKILLS[1 - index], dump(envelope))

    def test_empty_retrieval_is_indeterminate_not_definitive_no_match(self):
        records = []
        for index in range(2):
            envelope = self.evidence(index, hits=[])
            records.append(self.record(index, evidence=envelope))
            self.assertEqual(json.loads(envelope)["reason"], "retrieval_empty")
            self.assertEqual(records[-1]["reason"], "retrieval_empty")
        answer = self.render(records)["answer"]
        self.assertIn(
            "\u53ef\u80fd\u672a\u547d\u4e2d\u6216\u68c0\u7d22\u5f02\u5e38", answer
        )
        self.assertNotIn(NODES.NO_MATCH, answer)
        for teacher in self.selected["teachers"]:
            self.assertIn(teacher["name"], answer)

    def test_unknown_changed_pending_quarantined_or_cross_teacher_batch_rejected(self):
        valid = native_hit(METHODS[SUMMARY_SKILLS[0]])
        bad_cards = []
        for field, value in (
            ("skill_id", "unknown.method"),
            ("teacher_id", "unknown-teacher"),
            ("status", "pending"),
            ("status", "quarantined"),
            ("content_hash", "0" * 64),
            (
                "skill_id",
                REAL_DATA["sources"]["quarantined_methods"][0]["quarantine_id"],
            ),
        ):
            card = copy.deepcopy(METHODS[SUMMARY_SKILLS[0]])
            card[field] = value
            if field != "content_hash":
                card["content_hash"] = NODES.method_content_hash(card)
            bad_cards.append(card)
        bad_cards.append(METHODS[SUMMARY_SKILLS[1]])
        changed = copy.deepcopy(METHODS[SUMMARY_SKILLS[0]])
        changed["steps"][0] += " unauthorized change"
        changed["content_hash"] = NODES.method_content_hash(changed)
        bad_cards.append(changed)
        for card in bad_cards:
            with self.subTest(skill=card["skill_id"], status=card["status"]):
                envelope = json.loads(self.evidence(hits=[valid, native_hit(card)]))
                self.assertEqual(envelope["status"], "rejected")
                self.assertEqual(envelope["reason"], "retrieval_rejected")
                self.assertEqual(envelope["methods"], [])

    def test_metadata_body_disagreement_and_unexpected_wrappers_rejected(self):
        for field in ("teacher_id", "skill_id", "topic_id", "status", "content_hash"):
            for nested in (True, False):
                hit = native_hit(METHODS[SUMMARY_SKILLS[0]])
                metadata = (
                    hit["metadata"]["doc_metadata"] if nested else hit["metadata"]
                )
                metadata[field] = "different"
                with self.subTest(field=field, nested=nested):
                    self.assertEqual(
                        json.loads(self.evidence(hits=[hit]))["status"], "rejected"
                    )
        for prefix in (
            "title: fixture; content:",
            "question: fixture\nanswer:",
            "```json\n",
        ):
            hit = native_hit(METHODS[SUMMARY_SKILLS[0]])
            hit["content"] = prefix + hit["content"]
            self.assertEqual(
                json.loads(self.evidence(hits=[hit]))["status"], "rejected"
            )

    def test_same_teacher_other_topic_is_excluded_not_promoted(self):
        proposal = METHODS["bailu.material-proposals"]
        essay = METHODS["bailu.essay-topic-decomposition"]
        selected = self.select(
            proposal["examples"][0]["input"], topics=["shenlun.proposals"]
        )
        result = self.runtime["teacher_evidence"](
            "bailu",
            [native_hit(proposal), native_hit(essay)],
            selected["context"],
        )
        self.assertEqual(json.loads(result["evidence"])["methods"], [proposal])

    def test_all_five_real_cards_reach_only_their_own_exact_topic_branch(self):
        for card in METHODS.values():
            with self.subTest(skill=card["skill_id"]):
                selected = self.select(
                    card["examples"][0]["input"], topics=[card["topic_id"]]
                )
                teacher = next(
                    t
                    for t in selected["teachers"]
                    if t["teacher_id"] == card["teacher_id"]
                )
                self.assertIn(card["skill_id"], teacher["skill_ids"])
                self.assertEqual(
                    self.runtime["teacher_extract"](teacher)["teacher_id"],
                    card["teacher_id"],
                )
                evidence = self.runtime["teacher_evidence"](
                    card["teacher_id"], [native_hit(card)], selected["context"]
                )
                envelope = json.loads(evidence["evidence"])
                self.assertEqual(envelope["status"], "ok")
                self.assertEqual(envelope["methods"], [card])

    def test_redscarf_synthetic_solution_checks_all_four_options_with_16_operations(
        self,
    ):
        card = METHODS["honglingjin.option-substitution"]
        question = card["examples"][0]["input"]
        selected = self.select(question, topics=[card["topic_id"]])
        evidence = self.runtime["teacher_evidence"](
            "honglingjin", [native_hit(card)], selected["context"]
        )["evidence"]
        calculations = []
        for candidate in range(1, 5):
            other = 7 - candidate
            for operation, left, right in (
                ("subtract", 7, candidate),
                ("multiply", 2, candidate),
                ("multiply", 3, other),
                ("add", 2 * candidate, 3 * other),
            ):
                operands = {
                    "left": {"value": str(left), "unit": ""},
                    "right": {"value": str(right), "unit": ""},
                }
                calculations.append(
                    {
                        "operation": operation,
                        "operands": operands,
                        "result": NODES.calculate(operation, operands),
                    }
                )
        solution = {
            "status": "answered",
            "reason": "",
            "skill_ids": [card["skill_id"]],
            "evidence": [
                {
                    "source_id": card["sources"][0]["source_id"],
                    "quote": card["sources"][0]["quote"],
                }
            ],
            "conditions": [
                {
                    "skill_id": card["skill_id"],
                    "condition_id": c["condition_id"],
                    "quote": question,
                }
                for c in card["applicable"]
            ],
            "answer": "x=3",
            "steps": [
                "Substitute each option, check both equations and nonnegative integers; only C satisfies every condition."
            ],
            "material_quotes": [question],
            "calculations": calculations,
        }
        record = self.runtime["teacher_verify"](
            "honglingjin", dump(solution), dump(review()), evidence, selected["context"]
        )["result"]
        self.assertEqual(record["status"], "answered")
        self.assertEqual(len(json.loads(record["solution"])["calculations"]), 16)
        rendered = self.render([record], selected=selected)
        self.assertIn("x=3", rendered["answer"])
        self.assertIn(card["sources"][0]["quote"], rendered["answer"])

        # A letter alone cannot be matched to the checked numeric result.
        for answer, expected in (("C", "failed"), ("C, x=3", "answered")):
            with self.subTest(answer=answer):
                solution["answer"] = answer
                result = self.runtime["teacher_verify"](
                    "honglingjin",
                    dump(solution),
                    dump(review()),
                    evidence,
                    selected["context"],
                )["result"]
                self.assertEqual(result["status"], expected)

    def test_bailu_proposal_and_outline_synthetic_outputs_use_separate_real_cards(self):
        answers = {
            "bailu.material-proposals": "\u5f00\u9986\u524d\u68c0\u6d4b\u8bbe\u5907\u5e76\u8bb0\u5f55\u6545\u969c\uff1b\u5728\u73b0\u6709\u4eba\u5458\u5185\u8c03\u6574\u8f6e\u73ed\uff0c\u4fdd\u969c\u5348\u95f4\u501f\u8fd8\u3002",
            "bailu.essay-topic-decomposition": "\u7acb\u610f\u63d0\u7eb2\uff1a\u4fbf\u5229\u4e0e\u89c4\u8303\u5e76\u91cd\uff1b\u6574\u5408\u7a97\u53e3\u51cf\u5c11\u7b49\u5f85\uff0c\u540c\u65f6\u4fdd\u7559\u5fc5\u8981\u6838\u9a8c\u3002",
        }
        for key, answer in answers.items():
            with self.subTest(skill=key):
                card = METHODS[key]
                question = card["examples"][0]["input"]
                selected = self.select(question, topics=[card["topic_id"]])
                evidence = self.runtime["teacher_evidence"](
                    "bailu", [native_hit(card)], selected["context"]
                )["evidence"]
                solution = {
                    "status": "answered",
                    "reason": "",
                    "skill_ids": [key],
                    "evidence": [
                        {
                            "source_id": card["sources"][0]["source_id"],
                            "quote": card["sources"][0]["quote"],
                        }
                    ],
                    "conditions": [
                        {
                            "skill_id": key,
                            "condition_id": c["condition_id"],
                            "quote": question,
                        }
                        for c in card["applicable"]
                    ],
                    "answer": answer,
                    "steps": [
                        "Use only the supplied material and preserve its constraints."
                    ],
                    "material_quotes": [question],
                    "calculations": [],
                }
                record = self.runtime["teacher_verify"](
                    "bailu",
                    dump(solution),
                    dump(review()),
                    evidence,
                    selected["context"],
                )["result"]
                self.assertEqual(record["status"], "answered")
                rendered = self.render([record], selected=selected)
                self.assertIn(answer, rendered["answer"])
                self.assertEqual(json.loads(rendered["state"])["last_skill_ids"], [key])

    def test_synthetic_solutions_use_exact_real_sources_and_shallow_result_objects(
        self,
    ):
        records = [self.record(0), self.record(1)]
        for index, record in enumerate(records):
            self.assertEqual(record["status"], "answered")
            self.assertEqual(record["teacher_id"], SUMMARY_IDS[index])
            self.assertEqual(
                set(record),
                {"teacher_id", "status", "reason", "solution", "review", "evidence"},
            )
            self.assertTrue(all(type(value) is str for value in record.values()))
        answer = self.render(records)["answer"]
        for index, key in enumerate(SUMMARY_SKILLS):
            self.assertIn(SUMMARY_ANSWERS[index], answer)
            for source in METHODS[key]["sources"]:
                self.assertIn(source["quote"], answer)
                self.assertIn(source["commit"], answer)
        self.assertIn("\u793e\u533a\u6574\u7406", answer)
        self.assertIn(
            "\u4e0d\u6784\u6210\u4e8b\u5b9e\u6216\u6570\u5b66\u8bc1\u660e", answer
        )
        self.assertNotIn("**\u901a\u7528\u89e3\u6cd5", answer)

    def test_forged_sources_quotes_skills_conditions_or_material_rejected(self):
        mutations = [
            lambda s: s.update(skill_ids=[SUMMARY_SKILLS[1]]),
            lambda s: s["evidence"][0].update(source_id="invented-source"),
            lambda s: s["evidence"][0].update(quote=s["evidence"][0]["quote"][:-1]),
            lambda s: s["evidence"].append(copy.deepcopy(s["evidence"][0])),
            lambda s: s.update(conditions=s["conditions"][:-1]),
            lambda s: s["conditions"][0].update(condition_id="invented-condition"),
            lambda s: s["conditions"][0].update(quote="unsupported-material"),
            lambda s: s["conditions"].append(copy.deepcopy(s["conditions"][0])),
            lambda s: s.update(material_quotes=["unsupported-material"]),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                solution = summary_solution()
                mutate(solution)
                self.assertEqual(
                    self.record(solution=dump(solution))["status"], "failed"
                )

    def test_model_links_unknown_teacher_claims_and_word_limit_rejected(self):
        for answer in (
            "[untrusted](https://invalid.example/injection)",
            "\u865a\u6784\u8001\u5e08\u8ba4\u4e3a\u8fd9\u662f\u5b98\u65b9\u8ba4\u8bc1\u7b54\u6848",
            "\u674e\u68a6\u5706\u4fdd\u8bc1\u6ee1\u5206",
            "x" * 81,
        ):
            solution = summary_solution()
            solution["answer"] = answer
            self.assertEqual(self.record(solution=dump(solution))["status"], "failed")
        solution = summary_solution()
        solution["steps"] = ["javascript:alert(1)"]
        self.assertEqual(self.record(solution=dump(solution))["status"], "failed")

    def test_review_requires_all_true_booleans_and_no_issues(self):
        for field in review():
            changed = review()
            changed[field] = ["synthetic rejection"] if field == "issues" else False
            self.assertEqual(
                self.record(checked_review=dump(changed))["reason"], "review_failed"
            )
        for value in (1, "true", None):
            changed = review()
            changed["passed"] = value
            self.assertEqual(
                self.record(checked_review=dump(changed))["status"], "failed"
            )
        self.assertEqual(self.record(checked_review="not JSON")["status"], "failed")

    def test_malformed_duplicate_nonfinite_and_oversized_model_json_rejected(self):
        valid = dump(summary_solution())
        cases = [
            "",
            "[]",
            "null",
            valid[:-1],
            valid + " trailing",
            '{"status": NaN}',
            valid[:-1] + ',"status":"answered"}',
            "x" * 30001,
        ]
        for value in cases:
            with self.subTest(prefix=value[:30]):
                self.assertEqual(self.record(solution=value)["status"], "failed")
        self.assertEqual(
            self.record(solution="```json\n" + valid + "\n```")["status"], "answered"
        )

    def test_skip_is_visible_and_teacher_not_needed_cannot_silently_disappear(self):
        skipped = self.record(
            solution=dump(abstention("skip")), checked_review="unused"
        )
        self.assertEqual(skipped["status"], "skip")
        self.assertEqual(skipped["reason"], "not_applicable")
        forbidden = self.record(solution=dump(abstention("not_needed")))
        self.assertEqual(forbidden["status"], "failed")
        answer = self.render([skipped, None])["answer"]
        self.assertIn(self.selected["teachers"][0]["name"], answer)
        self.assertIn("\u4e3b\u52a8\u8df3\u8fc7", answer)

    def test_true_null_and_missing_iteration_positions_become_named_failures(self):
        first = self.record(0)
        for records in ([first, None], [first]):
            packed = json.loads(
                self.runtime["teacher_serialize"](records, self.selected["context"])[
                    "results"
                ]
            )
            self.assertEqual(
                [item["teacher_id"] for item in packed["items"]], SUMMARY_IDS
            )
            self.assertEqual(packed["items"][0]["status"], "answered")
            self.assertEqual(packed["items"][1]["reason"], "branch_failed")
            rendered = self.render(records)["answer"]
            self.assertIn(self.selected["teachers"][1]["name"], rendered)
            self.assertIn(
                "\u8be5\u8001\u5e08\u5206\u652f\u672a\u8fd4\u56de\u6709\u6548\u7ed3\u679c",
                rendered,
            )

    def test_wrong_order_duplicate_and_extra_iteration_results_do_not_change_ownership(
        self,
    ):
        first, second = self.record(0), self.record(1)
        for records in ([second, first], [first, first], {"not": "an array"}):
            packed = json.loads(
                self.runtime["teacher_serialize"](records, self.selected["context"])[
                    "results"
                ]
            )
            self.assertEqual(
                [item["teacher_id"] for item in packed["items"]], SUMMARY_IDS
            )
            self.assertEqual(len(packed["items"]), 2)
            self.assertEqual(packed["items"][1]["status"], "failed")
        packed = json.loads(
            self.runtime["teacher_serialize"](
                [first, second, first], self.selected["context"]
            )["results"]
        )
        self.assertIn("unexpected_results", packed["warnings"])
        self.assertEqual(len(packed["items"]), 2)

    def test_render_revalidates_serialized_results_and_does_not_trust_status(self):
        serialized = json.loads(
            self.runtime["teacher_serialize"](
                [self.record(), None], self.selected["context"]
            )["results"]
        )
        modified = json.loads(serialized["items"][0]["solution"])
        modified["answer"] = "[injected](https://invalid.example/unchecked)"
        serialized["items"][0]["solution"] = dump(modified)
        rendered = self.runtime["teacher_render"](
            self.selected["context"],
            dump(serialized),
            dump(abstention()),
            dump(review()),
        )
        self.assertNotIn("invalid.example", rendered["answer"])
        self.assertNotIn(SUMMARY_ANSWERS[0], rendered["answer"])
        self.assertIn(self.selected["teachers"][0]["name"], rendered["answer"])

    def test_general_growth_recomputes_exact_values_without_teacher_attribution(self):
        selected = self.select(GROWTH_QUESTION, topics=["xingce.data.growth"])
        self.assertEqual(selected["teachers"], [])
        rendered = self.render([], selected=selected, general=dump(growth_solution()))
        self.assertIn("**\u901a\u7528\u89e3\u6cd5", rendered["answer"])
        self.assertIn("4444.44", rendered["answer"])
        self.assertIn("555.56", rendered["answer"])
        self.assertIn(NODES.NO_MATCH, rendered["answer"])
        for candidate in REAL_DATA["sources"]["candidates"]:
            self.assertNotIn(candidate["name"], rendered["answer"])
        for current in ("5000", "5000.0", "5000.0000"):
            with self.subTest(current=current):
                solution = growth_solution()
                solution["calculations"][0]["result"]["values"]["current"] = current
                output = self.render([], selected=selected, general=dump(solution))[
                    "answer"
                ]
                self.assertIn(solution["answer"], output)

    def test_general_background_knowledge_still_requires_independent_review(self):
        # Synthetic structure fixture, not evidence of model factual accuracy.
        question = "Which is a mammal? A. whale B. carp"
        selected = self.select(question, topics=["xingce.common.knowledge"])
        solution = abstention("answered")
        solution.update(
            reason="",
            answer="A. A whale is a mammal.",
            steps=["General background knowledge: classify the two animals."],
            material_quotes=[question],
        )
        output = self.render([], selected=selected, general=dump(solution))["answer"]
        self.assertIn(solution["answer"], output)
        rejected = review()
        rejected.update(passed=False, facts_supported=False, issues=["Uncertain fact"])
        output = self.render(
            [], selected=selected, general=dump(solution), general_review=dump(rejected)
        )["answer"]
        self.assertNotIn(solution["answer"], output)

    def test_answer_fractions_are_checked_as_results_not_independent_denominators(self):
        selected = self.select(GROWTH_QUESTION, topics=["xingce.data.growth"])
        for fraction in ("5000/9", "5000 / 9", "5000÷9"):
            for answer in (
                fraction + "万元",
                "增长额约555.56万元（即" + fraction + "万元）。",
            ):
                with self.subTest(answer=answer):
                    solution = growth_solution()
                    solution["answer"] = answer
                    output = self.render([], selected=selected, general=dump(solution))[
                        "answer"
                    ]
                    self.assertIn("参考答案（模型生成，非官方答案）", output)
                    self.assertIn(fraction, output)
        for fraction in ("5000/8", "5000/0", "5000/9*2", "5000/9/2", "(5000/9)+1"):
            with self.subTest(fraction=fraction):
                solution = growth_solution()
                solution["answer"] = "增长额约555.56万元（即" + fraction + "万元）。"
                output = self.render([], selected=selected, general=dump(solution))[
                    "answer"
                ]
                self.assertNotIn("参考答案（模型生成，非官方答案）", output)

    def test_general_reviewer_replaces_only_explanation_prose(self):
        question = "Which is a mammal? A. whale B. carp"
        selected = self.select(question, topics=["xingce.common.knowledge"])
        solution = abstention("answered")
        solution.update(
            reason="",
            answer="A. whale",
            steps=["Extra speculative provenance is not needed."],
            material_quotes=[question],
        )
        original = copy.deepcopy(solution)
        checked = review()
        checked["reviewed_steps"] = ["A whale is a mammal, so A is correct."]
        output = self.render(
            [], selected=selected, general=dump(solution), general_review=dump(checked)
        )["answer"]
        self.assertIn(solution["answer"], output)
        self.assertIn(checked["reviewed_steps"][0], output)
        self.assertIn("独立复核整理", output)
        self.assertNotIn("Extra speculative provenance", output)
        self.assertEqual(solution, original)
        solution["answer"] = "A"
        checked["reviewed_steps"].append("Unrequested attribution for another option.")
        output = self.render(
            [], selected=selected, general=dump(solution), general_review=dump(checked)
        )["answer"]
        self.assertIn(checked["reviewed_steps"][0], output)
        self.assertNotIn(checked["reviewed_steps"][1], output)

    def test_general_reviewed_prose_cannot_bypass_existing_answer_gates(self):
        for mutation in (
            "new-number",
            "url",
            "empty",
            "answer-field",
            "missing-field",
            "false-review",
            "wrong-answer",
            "wrong-calculation",
            "invented-quote",
        ):
            selected = self.select(GROWTH_QUESTION, topics=["xingce.data.growth"])
            solution = growth_solution()
            if mutation in {"new-number", "url", "empty"}:
                question = "Which is a mammal? A. whale B. carp"
                selected = self.select(question, topics=["xingce.common.knowledge"])
                solution = abstention("answered")
                solution.update(
                    reason="",
                    answer="A. whale",
                    steps=["A whale is a mammal."],
                    material_quotes=[question],
                )
            checked = review()
            checked["reviewed_steps"] = ["先求基期量，再计算增长量。"]
            if mutation == "new-number":
                checked["reviewed_steps"] = ["结果是999999。"]
            elif mutation == "url":
                checked["reviewed_steps"] = ["See https://example.com for the answer."]
            elif mutation == "empty":
                checked["reviewed_steps"] = []
            elif mutation == "answer-field":
                checked["answer"] = solution["answer"]
            elif mutation == "missing-field":
                checked.pop("reviewed_steps")
            elif mutation == "false-review":
                checked.update(
                    passed=False, facts_supported=False, issues=["Unsupported"]
                )
                checked["reviewed_steps"] = []
            elif mutation == "wrong-answer":
                solution["answer"] = "625万元。"
            elif mutation == "wrong-calculation":
                solution["calculations"][0]["result"]["values"]["growth"] = "625.00"
            else:
                solution["material_quotes"] = ["invented original material"]
            with self.subTest(mutation=mutation):
                output = self.render(
                    [],
                    selected=selected,
                    general=dump(solution),
                    general_review=dump(checked),
                )["answer"]
                self.assertNotIn(solution["answer"], output)
        selected = self.select(GROWTH_QUESTION, topics=["xingce.data.growth"])
        solution = growth_solution()
        checked = review()
        checked["reviewed_steps"] = ["An unused mathematical rewrite claims 999999."]
        output = self.render(
            [], selected=selected, general=dump(solution), general_review=dump(checked)
        )["answer"]
        self.assertIn(solution["answer"], output)
        self.assertIn(solution["steps"][0], output)
        self.assertNotIn("999999", output)
        checked = review()
        checked["reviewed_steps"] = ["This field is not allowed on teacher reviews."]
        self.assertEqual(self.record(checked_review=dump(checked))["status"], "failed")

    def test_numeric_lists_inherit_explicit_units_and_person_alias_not_ordinal(self):
        for unit in ("人", "名", "件", "万元", "万人", "公里"):
            with self.subTest(unit=unit):
                recognized = self.runtime["_tn_numbers"]("100、80、70和50" + unit)
                expected_unit = "人" if unit == "名" else unit
                self.assertEqual(
                    recognized,
                    {(number, expected_unit) for number in (100, 80, 70, 50)},
                )
        recognized = self.runtime["_tn_numbers"]("第70名和第80名，共50名求职者。")
        self.assertIn((50, "人"), recognized)
        self.assertNotIn((70, "人"), recognized)
        self.assertNotIn((80, "人"), recognized)
        self.assertEqual(
            self.runtime["_tn_numbers"]("数量70，另有50人。"), {(70, ""), (50, "人")}
        )

    def test_unscaled_count_units_allow_integer_magnitudes_and_typed_zero_one(self):
        for unit in ("人", "件", "个", "家", "户"):
            question = f"现有50{unit}，求计算结果。"
            for magnitude_unit, increment in itertools.product(("", unit), (0, 1)):
                with self.subTest(
                    unit=unit, magnitude_unit=magnitude_unit, increment=increment
                ):
                    solution = arithmetic_solution(
                        question,
                        [arithmetic_record("add", 50, increment, magnitude_unit)],
                        str(50 + increment),
                    )
                    self.assertEqual(
                        self.check_arithmetic(question, solution), "answered"
                    )
        for value, expected in (("0", "1"), ("50.0", "51")):
            question = f"现有{value}人，求计算结果。"
            solution = arithmetic_solution(
                question,
                [arithmetic_record("add", value, 1)],
                expected,
            )
            self.assertEqual(self.check_arithmetic(question, solution), "answered")

    def test_fractional_and_negative_counts_are_not_dimensionless_sources(self):
        for value in ("7.5", "-7"):
            question = f"原始记录为{value}人，求加一的结果。"
            solution = arithmetic_solution(
                question, [arithmetic_record("add", value, 1)], "0"
            )
            with (
                self.subTest(value=value),
                self.assertRaisesRegex(ValueError, "operand|unit"),
            ):
                self.check_arithmetic(question, solution)

    def test_scaled_monetary_distance_and_mixed_units_are_not_stripped(self):
        for question, value in (
            ("原始数量50万人。", 50),
            ("原始数量50万元。", 50),
            ("原始数量50亿元。", 50),
            ("原始数量50元。", 50),
            ("原始距离50公里。", 50),
            ("原始面积50平方公里。", 50),
            ("原始数量50人，成本7元。", 50),
            ("原始数量50人，另有7件。", 50),
            ("原始数量80、70和50万元。", 70),
            ("原始数量80、70和50万人。", 70),
            ("原始距离80、70和50公里。", 70),
            ("原始数量80、70和50人，成本7元。", 70),
        ):
            solution = arithmetic_solution(
                question, [arithmetic_record("add", value, 1)], str(value + 1)
            )
            with (
                self.subTest(question=question),
                self.assertRaisesRegex(ValueError, "operand|unit"),
            ):
                self.check_arithmetic(question, solution)
        for unit in ("万人", "万元", "亿元", "元", "公里", "平方公里"):
            question = f"原始数量50{unit}。"
            for constant in (0, 1):
                solution = arithmetic_solution(
                    question,
                    [arithmetic_record("add", 50, constant, unit)],
                    str(50 + constant),
                )
                with (
                    self.subTest(unit=unit, constant=constant),
                    self.assertRaisesRegex(ValueError, "operand|unit"),
                ):
                    self.check_arithmetic(question, solution)

    def test_mixed_units_still_allow_present_typed_count_normalization(self):
        question = "现有50人，7件物品，成本8万元。"
        for unit, value in (("人", 50), ("件", 7)):
            for constant in (0, 1):
                solution = arithmetic_solution(
                    question,
                    [arithmetic_record("add", value, constant, unit)],
                    str(value + constant),
                )
                with self.subTest(unit=unit, constant=constant):
                    self.assertEqual(
                        self.check_arithmetic(question, solution), "answered"
                    )
        solution = arithmetic_solution(
            question, [arithmetic_record("add", 1, 0, "户")], "1"
        )
        with self.assertRaisesRegex(ValueError, "operand|unit"):
            self.check_arithmetic(question, solution)

    def test_recruitment_prefix_proves_missing_threshold_without_rewriting_solution(
        self,
    ):
        question, solution, prefix = recruitment_fixture()
        self.assertEqual(solution["answer"], "C. 258人")
        self.assertEqual(solution["calculations"][0], arithmetic_record("add", 69, 69))
        self.assertEqual(prefix, [arithmetic_record("subtract", 70, 1)])
        self.assertEqual(
            self.check_arithmetic(question, solution, prefix=prefix), "answered"
        )
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        checked = {**review(), "reviewed_steps": [], "calculation_prefix": prefix}
        output = self.render(
            [], selected=selected, general=dump(solution), general_review=dump(checked)
        )["answer"]
        self.assertIn("参考答案（模型生成，非官方答案）", output)
        self.assertIn(solution["answer"], output)
        for text in solution["steps"] + solution["material_quotes"]:
            self.assertIn(text, output)
        self.assertIn("subtract", output)
        self.assertIn("add", output)
        self.assertRegex(output, "前置|前缀|补充")
        self.assertIn("程序复算（只核验运算，不证明列式）", output)

    def test_recruitment_without_prefix_never_trusts_implicit_threshold_minus_one(self):
        question, solution, _ = recruitment_fixture()
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        for prefix in (None, []):
            with (
                self.subTest(prefix=prefix),
                self.assertRaisesRegex(ValueError, "operand|unit"),
            ):
                self.check_arithmetic(question, solution, prefix=prefix)
        output = self.render([], selected=selected, general=dump(solution))["answer"]
        self.assertNotIn(solution["answer"], output)
        self.assertNotIn("参考答案（模型生成，非官方答案）", output)

    def test_typed_person_recruitment_chain_uses_shared_units_and_one_person(self):
        question, solution, prefix = recruitment_fixture(unit="人")
        self.assertIn("100、80、70和50人", question)
        self.assertIn("70名", question)
        self.assertEqual(prefix[0]["operands"]["right"], {"value": "1", "unit": "人"})
        self.assertEqual(
            self.check_arithmetic(question, solution, prefix=prefix), "answered"
        )
        with self.assertRaisesRegex(ValueError, "operand|unit"):
            self.check_arithmetic(question, solution)

    def test_recruitment_prefix_generalizes_to_independent_threshold_and_capacities(
        self,
    ):
        for unit in ("", "人"):
            question, solution, prefix = recruitment_fixture(
                (60, 45, 30, 15), 40, unit=unit
            )
            self.assertEqual(solution["answer"], "C. 124人")
            self.assertNotIn("258", dump((question, solution, prefix)))
            self.assertEqual(prefix[0], arithmetic_record("subtract", 40, 1, unit))
            self.assertEqual(
                self.check_arithmetic(question, solution, prefix=prefix), "answered"
            )
            selected = self.select(question, topics=["xingce.quantity.arithmetic"])
            checked = {**review(), "reviewed_steps": [], "calculation_prefix": prefix}
            output = self.render(
                [],
                selected=selected,
                general=dump(solution),
                general_review=dump(checked),
            )["answer"]
            self.assertIn(solution["answer"], output)

    def test_prefix_all_four_basic_operations_can_feed_later_prefix_operands(self):
        question, solution, prefix = recruitment_fixture()
        prefix.extend(
            [
                arithmetic_record("add", 69, 1),
                arithmetic_record("multiply", 69, 100),
                arithmetic_record("divide", 6900, 100),
            ]
        )
        self.assertEqual(
            self.check_arithmetic(question, solution, prefix=prefix), "answered"
        )

    def test_prefix_is_checked_before_original_and_cannot_use_future_results(self):
        question, solution, prefix = recruitment_fixture()
        for invalid in (
            [arithmetic_record("add", 69, 1), *prefix],
            [arithmetic_record("add", 138, 1), *prefix],
            [arithmetic_record("subtract", 69, 0)],
        ):
            with (
                self.subTest(prefix=invalid),
                self.assertRaisesRegex(ValueError, "operand|unit"),
            ):
                self.check_arithmetic(question, solution, prefix=invalid)

    def test_prefix_rejects_wrong_arithmetic_units_types_metadata_and_schema(self):
        question, solution, prefix = recruitment_fixture()
        changes = (
            (("result", "values", "result"), "68.00"),
            (("result", "values", "result"), 69),
            (("result", "values", "result"), True),
            (("result", "values", "result"), "NaN"),
            (("result", "values"), {"result": "69.00", "extra": "69.00"}),
            (("result", "unit"), "人"),
            (("result", "operation"), "add"),
            (("result", "places"), True),
            (("result", "places"), 7),
            (("result", "rounding"), "unrecognized"),
            (("operands", "left", "value"), True),
            (("operands", "left", "value"), 70),
            (("operands", "left", "value"), "70-1"),
            (("operands", "left", "unit"), "人"),
            (("operands", "left", "unit"), "DO-NOT-LEAK-UNIT"),
            (("operands", "left", "extra"), "not allowed"),
            (("operation",), "unknown-operation"),
            (("extra",), "not allowed"),
        )
        for path, value in changes:
            malformed = copy.deepcopy(prefix)
            item = malformed[0]
            for key in path[:-1]:
                item = item[key]
            item[path[-1]] = value
            with self.subTest(path=path, value=value), self.assertRaises(ValueError):
                self.check_arithmetic(question, solution, prefix=malformed)
        for missing in ("operation", "operands", "result"):
            malformed = copy.deepcopy(prefix)
            malformed[0].pop(missing)
            with self.subTest(missing=missing), self.assertRaises(ValueError):
                self.check_arithmetic(question, solution, prefix=malformed)
        for malformed in ({}, "[]", True, [None], [1]):
            with self.subTest(prefix=malformed), self.assertRaises(ValueError):
                self.check_arithmetic(question, solution, prefix=malformed)
        for invalid in (
            [arithmetic_record("subtract", 71, 2)],
            [arithmetic_record("subtract", 70, 1, "件")],
            [arithmetic_record("subtract", 70, 1, "人")],
        ):
            with (
                self.subTest(prefix=invalid),
                self.assertRaisesRegex(ValueError, "operand|unit"),
            ):
                self.check_arithmetic(question, solution, prefix=invalid)

    def test_growth_operations_are_forbidden_in_prefix_even_when_correct(self):
        solution = growth_solution()
        with self.assertRaises(ValueError):
            self.check_arithmetic(
                GROWTH_QUESTION, solution, prefix=solution["calculations"]
            )

    def test_prefix_maximum_sixteen_and_combined_maximum_forty_are_enforced(self):
        question, solution, prefix = recruitment_fixture()
        maximum_prefix = prefix * 16
        self.assertEqual(
            self.check_arithmetic(question, solution, prefix=maximum_prefix), "answered"
        )
        with self.assertRaises(ValueError):
            self.check_arithmetic(question, solution, prefix=prefix * 17)
        solution["calculations"].extend(
            copy.deepcopy(solution["calculations"][-1:]) * 20
        )
        self.assertEqual(len(solution["calculations"]) + len(maximum_prefix), 40)
        self.assertEqual(
            self.check_arithmetic(question, solution, prefix=maximum_prefix), "answered"
        )
        solution["calculations"].append(copy.deepcopy(solution["calculations"][-1]))
        with self.assertRaises(ValueError):
            self.check_arithmetic(question, solution, prefix=maximum_prefix)

    def test_general_optional_prefix_preserves_seven_field_review_contract(self):
        question, solution, prefix = recruitment_fixture()
        solution["calculations"] = prefix + solution["calculations"]
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        original_review = {**review(), "reviewed_steps": []}
        for checked in (original_review, {**original_review, "calculation_prefix": []}):
            output = self.render(
                [],
                selected=selected,
                general=dump(solution),
                general_review=dump(checked),
            )["answer"]
            self.assertIn(solution["answer"], output)
        invalid_reviews = [
            {**original_review, "calculation_prefix": value}
            for value in (None, {}, "[]", True)
        ]
        invalid_reviews.extend(
            [
                {**review(), "calculation_prefix": []},
                {
                    **original_review,
                    "calculation_prefix": [],
                    "answer": solution["answer"],
                },
            ]
        )
        for checked in invalid_reviews:
            with self.subTest(review=checked):
                output = self.render(
                    [],
                    selected=selected,
                    general=dump(solution),
                    general_review=dump(checked),
                )["answer"]
                self.assertNotIn("参考答案（模型生成，非官方答案）", output)

    def test_nonempty_prefix_requires_original_calculations_and_answered_status(self):
        question = "Which is a mammal? A. whale B. carp"
        selected = self.select(question, topics=["xingce.common.knowledge"])
        prefix = [arithmetic_record("add", 1, 0)]
        solution = arithmetic_solution(question, [], "A. whale")
        for candidate in (solution, abstention("skip"), abstention("not_needed")):
            with (
                self.subTest(status=candidate["status"]),
                self.assertRaises(ValueError),
            ):
                self.runtime["_tn_check_answer"](
                    candidate,
                    review(),
                    None,
                    "",
                    json.loads(selected["context"]),
                    self.runtime["_tn_catalog"](),
                    calculation_prefix=prefix,
                )
        checked = {
            **review(),
            "reviewed_steps": ["A whale is a mammal."],
            "calculation_prefix": prefix,
        }
        output = self.render(
            [], selected=selected, general=dump(solution), general_review=dump(checked)
        )["answer"]
        self.assertNotIn(solution["answer"], output)

    def test_prefix_only_answer_cannot_launder_wrong_original_numeric_or_fraction_answer(
        self,
    ):
        question, solution, prefix = recruitment_fixture()
        prefix += copy.deepcopy(solution["calculations"])
        prefix.append(arithmetic_record("add", 258, 1))
        self.assertEqual(
            self.check_arithmetic(question, solution, prefix=prefix), "answered"
        )
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        checked = {**review(), "reviewed_steps": [], "calculation_prefix": prefix}
        for wrong_answer in ("C. 259人", "259/1人", "C. 69人"):
            solution["answer"] = wrong_answer
            with self.subTest(answer=wrong_answer):
                with self.assertRaises(ValueError):
                    self.check_arithmetic(question, solution, prefix=prefix)
                output = self.render(
                    [],
                    selected=selected,
                    general=dump(solution),
                    general_review=dump(checked),
                )["answer"]
                self.assertNotIn(wrong_answer, output)
                self.assertNotIn("参考答案（模型生成，非官方答案）", output)
                self.assertNotIn("subtract", output)

    def test_valid_prefix_does_not_replace_wrong_original_arithmetic(self):
        question, solution, prefix = recruitment_fixture()
        solution["calculations"][0]["result"]["values"]["result"] = "137.00"
        with self.assertRaisesRegex(ValueError, "arithmetic"):
            self.check_arithmetic(question, solution, prefix=prefix)
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        checked = {**review(), "reviewed_steps": [], "calculation_prefix": prefix}
        output = self.render(
            [], selected=selected, general=dump(solution), general_review=dump(checked)
        )["answer"]
        self.assertNotIn(solution["answer"], output)
        self.assertNotIn("subtract", output)

    def test_prefix_is_not_displayed_when_independent_review_fails(self):
        question, solution, prefix = recruitment_fixture()
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        checked = {
            **review(),
            "passed": False,
            "issues": ["Synthetic independent rejection"],
            "reviewed_steps": [],
            "calculation_prefix": prefix,
        }
        output = self.render(
            [], selected=selected, general=dump(solution), general_review=dump(checked)
        )["answer"]
        self.assertNotIn("参考答案（模型生成，非官方答案）", output)
        self.assertNotIn(solution["answer"], output)
        self.assertNotIn("subtract", output)

    def test_prefix_cannot_satisfy_growth_role_or_authorize_wrong_growth_answer(self):
        prefix = [arithmetic_record("multiply", 5000, "0.125", "万元", right_unit="")]
        original = growth_solution()
        wrong_role = copy.deepcopy(original)
        operands = {"base": "5000", "rate": "12.5%", "unit": "万元"}
        wrong_role["calculations"] = [
            {
                "operation": "growth_from_base",
                "operands": operands,
                "result": NODES.calculate("growth_from_base", operands),
            }
        ]
        wrong_operation = copy.deepcopy(original)
        wrong_operation["calculations"] = copy.deepcopy(prefix)
        for solution in (original, wrong_role, wrong_operation):
            solution["answer"] = "625万元"
            with (
                self.subTest(operation=solution["calculations"][0]["operation"]),
                self.assertRaises(ValueError),
            ):
                self.check_arithmetic(GROWTH_QUESTION, solution, prefix=prefix)

    def test_prefix_validation_and_rendering_preserve_raw_original_record(self):
        question, solution, prefix = recruitment_fixture()
        checked = {
            **review(),
            "reviewed_steps": ["REVIEWER-REWRITE-MUST-NOT-APPEAR"],
            "calculation_prefix": prefix,
        }
        original, original_review = copy.deepcopy(solution), copy.deepcopy(checked)
        self.assertEqual(
            self.check_arithmetic(question, solution, prefix=prefix), "answered"
        )
        self.assertEqual(solution, original)
        self.assertEqual(checked, original_review)
        raw_solution, raw_review = dump(solution), dump(checked)
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        checker = mock.Mock(wraps=self.runtime["_tn_check_answer"])
        with mock.patch.dict(self.runtime, {"_tn_check_answer": checker}):
            output = self.render(
                [], selected=selected, general=raw_solution, general_review=raw_review
            )["answer"]
        self.assertEqual(checker.call_count, 1)
        self.assertEqual(checker.call_args.args[0], original)
        self.assertEqual(checker.call_args.args[1], review())
        self.assertEqual(checker.call_args.kwargs["calculation_prefix"], prefix)
        self.assertEqual(raw_solution, dump(original))
        self.assertEqual(raw_review, dump(original_review))
        self.assertNotIn("REVIEWER-REWRITE-MUST-NOT-APPEAR", output)
        self.assertIn(solution["answer"], output)
        self.assertNotIn("calculation_prefix", checker.call_args.args[0])

    def test_teacher_reviews_reject_even_empty_calculation_prefix(self):
        self.assertEqual(self.record()["status"], "answered")
        for prefix in ([], [arithmetic_record("add", 1, 0)]):
            checked = {**review(), "calculation_prefix": prefix}
            with self.subTest(prefix=prefix):
                self.assertEqual(
                    self.record(checked_review=dump(checked))["status"], "failed"
                )
        teacher_solution = summary_solution()
        teacher_solution["calculations"] = [arithmetic_record("add", 1, 0)]
        self.assertEqual(
            self.record(solution=dump(teacher_solution))["status"], "answered"
        )
        with self.assertRaises(ValueError):
            self.runtime["_tn_check_answer"](
                teacher_solution,
                review(),
                json.loads(self.evidence()),
                SUMMARY_IDS[0],
                json.loads(self.selected["context"]),
                self.runtime["_tn_catalog"](),
                calculation_prefix=[arithmetic_record("add", 1, 0)],
            )
        question, solution, prefix = recruitment_fixture()
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        with self.assertRaises(TypeError):
            self.runtime["_tn_check_answer"](
                solution,
                review(),
                None,
                "",
                json.loads(selected["context"]),
                self.runtime["_tn_catalog"](),
                prefix,
            )

    def test_unbound_operand_diagnostic_is_safe_chinese_and_never_raw_exception(self):
        question, solution, _ = recruitment_fixture()
        selected = self.select(question, topics=["xingce.quantity.arithmetic"])
        output = self.render([], selected=selected, general=dump(solution))["answer"]
        self.assertIn("单位", output)
        self.assertRegex(output, "来源|依据|原题")
        self.assertNotIn("invented arithmetic operand or unit", output)
        self.assertNotIn("ValueError", output)
        self.assertNotIn(solution["answer"], output)
        for error in (ValueError("DO-NOT-LEAK"), KeyError("DO-NOT-LEAK")):
            with mock.patch.dict(
                self.runtime, {"_tn_check_answer": mock.Mock(side_effect=error)}
            ):
                output = self.render([], selected=selected, general=dump(solution))[
                    "answer"
                ]
            self.assertNotIn("DO-NOT-LEAK", output)
            self.assertNotIn("参考答案（模型生成，非官方答案）", output)

    def test_general_prefix_prompt_is_generic_not_recruitment_answer_keyed(self):
        prompt = self.runtime["GENERAL_REVIEW_PROMPT"]
        self.assertIn("calculation_prefix", prompt)
        self.assertRegex(prompt, r"(?:阈值|门槛|目标).{0,20}(?:减|-)\s*1")
        self.assertIn("16", prompt)
        for name in ("GENERAL_PROMPT", "GENERAL_REVIEW_PROMPT"):
            self.assertNotIn("258", self.runtime[name])
            self.assertNotIn("100、80、70和50", self.runtime[name])

    def test_explicit_income_and_year_on_year_wording_is_not_fixed_template_only(self):
        questions = [
            "\u67d0\u4f01\u4e1a\u73b0\u671f\u6536\u51655000\u4e07\u5143\uff0c\u540c\u6bd4\u589e\u957f12.5%\uff0c\u589e\u957f\u989d\u662f\u591a\u5c11\uff1f",
            "\u672c\u671f\u8425\u4e1a\u6536\u51655000\u4e07\u5143\uff0c\u73af\u6bd4\u589e\u957f\u738712.5%\uff0c\u6c42\u589e\u957f\u91cf\u3002",
        ]
        for question in questions:
            with self.subTest(question=question):
                selected = self.select(question, topics=["xingce.data.growth"])
                solution = growth_solution()
                solution["material_quotes"] = [question]
                rendered = self.render([], selected=selected, general=dump(solution))
                self.assertIn("**\u901a\u7528\u89e3\u6cd5", rendered["answer"])
                self.assertIn("555.56", rendered["answer"])

    def test_income_wording_does_not_allow_current_times_rate_or_base_role_swap(self):
        question = "\u67d0\u4f01\u4e1a\u73b0\u671f\u6536\u51655000\u4e07\u5143\uff0c\u540c\u6bd4\u589e\u957f12.5%\uff0c\u589e\u957f\u989d\u662f\u591a\u5c11\uff1f"
        selected = self.select(question, topics=["xingce.data.growth"])
        for operation, operands in [
            (
                "growth_from_base",
                {"base": "5000", "rate": "12.5%", "unit": "\u4e07\u5143"},
            ),
            (
                "multiply",
                {
                    "left": {"value": "5000", "unit": "\u4e07\u5143"},
                    "right": {"value": "0.125", "unit": ""},
                },
            ),
        ]:
            with self.subTest(operation=operation):
                solution = growth_solution()
                solution.update(
                    answer="625.00",
                    material_quotes=[question],
                    calculations=[
                        {
                            "operation": operation,
                            "operands": operands,
                            "result": NODES.calculate(operation, operands),
                        }
                    ],
                )
                rendered = self.render([], selected=selected, general=dump(solution))
                self.assertNotIn("**\u901a\u7528\u89e3\u6cd5", rendered["answer"])
                self.assertNotIn("625.00", rendered["answer"])

    def test_general_growth_rejects_625_role_swap_result_and_unit_forgery(self):
        selected = self.select(GROWTH_QUESTION, topics=["xingce.data.growth"])
        cases = []
        wrong_role = growth_solution()
        operands = {"base": "5000", "rate": "12.5%", "unit": "\u4e07\u5143"}
        wrong_role["calculations"] = [
            {
                "operation": "growth_from_base",
                "operands": operands,
                "result": NODES.calculate("growth_from_base", operands),
            }
        ]
        wrong_role["answer"] = "625"
        cases.append(wrong_role)
        for field in ("result", "unit"):
            bad = growth_solution()
            if field == "result":
                bad["calculations"][0]["result"]["values"]["growth"] = "625.00"
            else:
                bad["calculations"][0]["operands"]["unit"] = ""
                bad["calculations"][0]["result"]["unit"] = ""
            cases.append(bad)
        for solution in cases:
            rendered = self.render([], selected=selected, general=dump(solution))
            self.assertNotIn("**\u901a\u7528\u89e3\u6cd5", rendered["answer"])
            self.assertNotIn("625", rendered["answer"])

    def test_general_is_independent_after_failures_but_ignored_when_any_teacher_valid(
        self,
    ):
        general = summary_solution()
        general.update(skill_ids=[], evidence=[], conditions=[])
        answer = self.render([None, None], general=dump(general))["answer"]
        self.assertIn("**\u901a\u7528\u89e3\u6cd5", answer)
        answer = self.render(
            [self.record(), None], general="unchecked attacker output"
        )["answer"]
        self.assertNotIn("unchecked attacker output", answer)
        self.assertNotIn("**\u901a\u7528\u89e3\u6cd5", answer)

    def test_classifier_failure_does_not_skip_general_or_fabricate_teachers(self):
        for text in (
            "not JSON",
            '{"topic_ids":["not-in-taxonomy"]}',
            '{"complete":NaN}',
        ):
            selected = self.select(GROWTH_QUESTION, model_text=text)
            self.assertEqual(selected["teachers"], [])
            rendered = self.render(
                [], selected=selected, general=dump(growth_solution())
            )
            self.assertIn("555.56", rendered["answer"])
            self.assertIn(
                "\u9898\u578b\u8bc6\u522b\u8f93\u51fa\u65e0\u6548", rendered["answer"]
            )

    def test_incomplete_question_blocks_teacher_and_general_claims(self):
        selected = self.select(model_text=classification(complete=False))
        self.assertEqual(selected["teachers"], [])
        rendered = self.render([], selected=selected, general=dump(summary_solution()))
        self.assertIn("\u6750\u6599\u4e0d\u5b8c\u6574", rendered["answer"])
        self.assertNotIn(SUMMARY_ANSWERS[0], rendered["answer"])
        self.assertEqual(rendered["state"], "")

    def test_followup_preserves_question_and_passes_request_only_to_own_evidence(self):
        first = self.render([self.record(0), self.record(1)])
        command = "\u5c55\u5f00\u7b2c\u4e8c\u4f4d\u8001\u5e08"
        selected = self.select(command, state=first["state"])
        context = json.loads(selected["context"])
        self.assertEqual(context["question"], SUMMARY_QUESTION)
        self.assertEqual(context["request"]["kind"], "expand")
        self.assertEqual(context["request"]["target_teacher_id"], SUMMARY_IDS[1])
        self.assertEqual([t["teacher_id"] for t in selected["teachers"]], SUMMARY_IDS)
        for index in range(2):
            envelope = json.loads(self.evidence(index, selected=selected))
            self.assertEqual(envelope["request"]["text"], command)
            self.assertEqual(
                [m["teacher_id"] for m in envelope["methods"]], [SUMMARY_IDS[index]]
            )
            self.assertNotIn("solution", envelope)
        second = self.render(
            [self.record(0, selected=selected), self.record(1, selected=selected)],
            selected=selected,
        )
        self.assertEqual(json.loads(second["state"])["turn"], 2)

    def test_preference_is_display_only_and_new_question_resets_slots(self):
        first = self.render([self.record(0), self.record(1)])
        preferred = self.select(
            "\u4ee5\u540e\u4f18\u5148\u7b2c\u4e8c\u4f4d\u8001\u5e08",
            state=first["state"],
        )
        self.assertEqual([t["teacher_id"] for t in preferred["teachers"]], SUMMARY_IDS)
        rendered = self.render(
            [self.record(0, selected=preferred), self.record(1, selected=preferred)],
            selected=preferred,
        )
        saved = json.loads(rendered["state"])
        self.assertEqual(saved["last_teacher_ids"], list(reversed(SUMMARY_IDS)))
        self.assertEqual(saved["preferences"], [SUMMARY_IDS[1]])
        new = self.select(
            GROWTH_QUESTION, state=rendered["state"], topics=["xingce.data.growth"]
        )
        context = json.loads(new["context"])
        self.assertIsNone(context["previous"])
        self.assertEqual(context["teachers"], [])
        self.assertEqual(context["preferences"], [SUMMARY_IDS[1]])
        fresh = self.render([], selected=new, general=dump(growth_solution()))
        self.assertEqual(json.loads(fresh["state"])["turn"], 1)
        self.assertEqual(json.loads(fresh["state"])["last_skill_ids"], [])
        self.assertNotIn(SUMMARY_ANSWERS[0], fresh["answer"])

    def test_invalid_expired_unknown_teacher_and_oversized_state_fail_closed(self):
        state = json.loads(self.render([self.record(), None])["state"])
        expired = {**state, "turn": 8}
        forged = {**state, "last_teacher_ids": ["unknown-teacher"]}
        for previous in ("", "not JSON", dump(expired), dump(forged), "x" * 12001):
            prepared = self.runtime["teacher_prepare"](
                "\u5c55\u5f00\u7b2c\u4e8c\u4f4d\u8001\u5e08", previous
            )
            self.assertEqual(prepared["question"], "")
            self.assertEqual(json.loads(prepared["request"])["kind"], "invalid")
        prepared = self.runtime["teacher_prepare"]("x" * 6001, "")
        self.assertEqual(prepared["question"], "")
        self.assertEqual(prepared["state"], "")

    def test_general_challenge_and_step_followups_recompute_without_historical_answer(
        self,
    ):
        selected = self.select(GROWTH_QUESTION, topics=["xingce.data.growth"])
        first = self.render([], selected=selected, general=dump(growth_solution()))
        for command, kind in (
            ("\u4e3a\u4ec0\u4e48\u4e0d\u662f625", "challenge"),
            ("\u89e3\u91ca\u7b2c\u4e00\u6b65", "step"),
        ):
            with self.subTest(kind=kind):
                followup = self.select(
                    command,
                    state=first["state"],
                    model_text="malformed classifier fixture",
                )
                context = json.loads(followup["context"])
                self.assertEqual(context["question"], GROWTH_QUESTION)
                self.assertEqual(context["request"]["kind"], kind)
                self.assertEqual(context["topic_ids"], ["xingce.data.growth"])
                self.assertNotIn("answer", context["previous"])
                rendered = self.render(
                    [], selected=followup, general=dump(growth_solution())
                )
                self.assertIn("555.56", rendered["answer"])
                self.assertEqual(json.loads(rendered["state"])["turn"], 2)

    def test_fixed_model_error_outputs_are_not_reported_as_success(self):
        failure = '{"status":"failed","reason":"model_failure"}'
        record = self.record(solution=failure, checked_review=failure)
        self.assertEqual(record["status"], "failed")
        self.assertEqual(record["reason"], "model_failure")
        selected = self.select(GROWTH_QUESTION, model_text=failure)
        rendered = self.render(
            [], selected=selected, general=failure, general_review=failure
        )
        self.assertNotIn("555.56", rendered["answer"])
        self.assertNotIn("**\u901a\u7528\u89e3\u6cd5", rendered["answer"])
        self.assertIn("\u672a\u5c55\u793a\u5176\u7b54\u6848", rendered["answer"])

    def test_transport_failure_is_not_reported_as_bad_question_or_failed_evidence(self):
        failure = '{"status":"failed","reason":"model_failure"}'
        selected = self.select(GROWTH_QUESTION, model_text=failure)
        output = self.render(
            [], selected=selected, general=failure, general_review=failure
        )["answer"]
        self.assertIn("\u6a21\u578b\u8c03\u7528\u5931\u8d25", output)
        self.assertIn("Model Provider", output)
        self.assertNotIn(
            "\u901a\u7528\u89e3\u6cd5\u672a\u901a\u8fc7\u6750\u6599", output
        )
        checked = self.record(checked_review=failure)
        self.assertEqual(checked["reason"], "model_failure")

    def test_malformed_model_json_still_has_distinct_validation_failure(self):
        selected = self.select(GROWTH_QUESTION, model_text="not JSON")
        output = self.render([], selected=selected, general="not JSON")["answer"]
        self.assertIn("\u8f93\u51fa\u65e0\u6548", output)
        self.assertNotIn("Model Provider", output)
        fake_error = (
            '{"status":"failed","reason":"model_failure","error":"DO-NOT-LEAK"}'
        )
        output = self.render([], selected=selected, general=fake_error)["answer"]
        self.assertNotIn("DO-NOT-LEAK", output)

    def test_tampered_teacher_enumeration_context_is_rejected_at_render(self):
        context = json.loads(self.selected["context"])
        context["teachers"] = context["teachers"][:1]
        rendered = self.runtime["teacher_render"](
            dump(context), "{}", dump(summary_solution()), dump(review())
        )
        self.assertEqual(rendered["state"], "")
        self.assertIn("\u6821\u9a8c\u5931\u8d25", rendered["answer"])
        self.assertNotIn(SUMMARY_ANSWERS[0], rendered["answer"])

    def test_capacity_keeps_all_positions_and_never_truncates_as_success(self):
        records = [self.record(0), self.record(1)]
        limit = max(len(dump(record)) for record in records) + 500
        with mock.patch.dict(self.runtime, {"_TN_BUNDLE": limit}):
            serialized = self.runtime["teacher_serialize"](
                records, self.selected["context"]
            )["results"]
            packed = json.loads(serialized)
            self.assertLessEqual(len(serialized), limit)
            self.assertEqual([r["teacher_id"] for r in packed["items"]], SUMMARY_IDS)
            self.assertTrue(
                any(r["reason"] == "capacity_pending" for r in packed["items"])
            )
            self.assertIn("capacity_pending", packed["warnings"])
        with mock.patch.dict(self.runtime, {"_TN_OUTPUT": 1700}):
            rendered = self.render(records)
            self.assertLessEqual(len(rendered["answer"]), 1700)
            self.assertIn("\u5f85\u5904\u7406", rendered["answer"])
            for teacher in self.selected["teachers"]:
                self.assertIn(teacher["name"], rendered["answer"])
        rendered = self.render(records)
        self.assertLessEqual(len(rendered["answer"]), 16000)
        self.assertLessEqual(len(rendered["state"]), 12000)

    def test_over_30_synthetic_teachers_remain_explicit_pending_not_global_top_k(self):
        synthetic = BASE.synthetic_data(31)
        with mock.patch.dict(self.runtime, {"KAOGONG_CATALOG": synthetic}):
            selected = self.select(BASE.QUESTION, topics=[BASE.TOPIC])
            context = json.loads(selected["context"])
            self.assertEqual(len(selected["teachers"]), 30)
            self.assertEqual(len(context["pending"]), 1)
            expected = NODES.enumerate_teachers(
                [BASE.TOPIC], NODES.validate_catalog(**synthetic)
            )["teachers"]
            self.assertEqual(context["teachers"] + context["pending"], expected)
            rendered = self.render([None] * 30, selected=selected)
            self.assertIn(
                context["pending"][0]["name"],
                rendered["answer"].replace("\\(", "(").replace("\\)", ")"),
            )
            self.assertIn("\u672c\u8f6e\u672a\u5b8c\u6210", rendered["answer"])


class NativeGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dsl = WORKFLOW.build_teacher_workflow(SOURCE, REAL_DATA, BINDING)
        cls.nodes = {node["id"]: node for node in cls.dsl["workflow"]["graph"]["nodes"]}

    def test_all_18_nodes_and_only_native_same_scope_wiring(self):
        roots = [
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
        children = [
            "kg_iter_start",
            "kg_extract",
            "kg_retrieval",
            "kg_evidence",
            "kg_solve",
            "kg_review",
            "kg_verify",
        ]
        self.assertEqual(set(self.nodes), set(roots + children))
        edges = self.dsl["workflow"]["graph"]["edges"]
        self.assertEqual(len(edges), 16)
        self.assertEqual(
            {(e["source"], e["target"]) for e in edges},
            set(itertools.pairwise(roots)) | set(itertools.pairwise(children)),
        )
        for edge in edges:
            self.assertEqual(edge["sourceHandle"], "source")
            self.assertEqual(edge["targetHandle"], "target")
            self.assertEqual(
                self.nodes[edge["source"]]["data"].get("container_id"),
                self.nodes[edge["target"]]["data"].get("container_id"),
            )
        for node_id in children:
            self.assertEqual(self.nodes[node_id]["parentId"], "kg_iteration")
            self.assertEqual(
                self.nodes[node_id]["data"]["container_id"], "kg_iteration"
            )

    def test_iteration_native_parallel_three_preserves_empty_and_failed_slots_contract(
        self,
    ):
        data = self.nodes["kg_iteration"]["data"]
        self.assertIs(data["is_parallel"], True)
        self.assertEqual(data["parallel_nums"], 3)
        self.assertEqual(data["error_handle_mode"], "continue-on-error")
        self.assertIs(data["flatten_output"], False)
        self.assertEqual(data["start_node_id"], "kg_iter_start")
        self.assertEqual(data["iterator_selector"], ["kg_select", "teachers"])
        self.assertEqual(data["output_selector"], ["kg_verify", "result"])
        self.assertEqual(
            self.nodes["kg_select"]["data"]["outputs"]["teachers"]["type"],
            "array[object]",
        )
        self.assertEqual(
            self.nodes["kg_verify"]["data"]["outputs"]["result"]["type"], "object"
        )
        self.assertIn(
            {"variable": "results", "value_selector": ["kg_iteration", "output"]},
            self.nodes["kg_serialize"]["data"]["variables"],
        )

    def test_native_manual_metadata_is_dynamic_teacher_and_literal_approved(self):
        data = self.nodes["kg_retrieval"]["data"]
        self.assertEqual(data["metadata_filtering_mode"], "manual")
        self.assertEqual(
            data["metadata_filtering_conditions"],
            {
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
        )
        self.assertEqual(data["dataset_ids"], [BINDING["dataset_id"]])
        self.assertEqual(data["retrieval_mode"], "multiple")
        self.assertEqual(data["multiple_retrieval_config"]["top_k"], 5)
        self.assertFalse(data["multiple_retrieval_config"]["reranking_enable"])
        self.assertEqual(data["query_variable_selector"], ["kg_select", "query"])

    def test_llms_use_text_json_prompts_no_sampling_memory_or_structured_output(self):
        llms = [node for node in self.nodes.values() if node["data"]["type"] == "llm"]
        self.assertEqual(len(llms), 5)
        for node in llms:
            data = node["data"]
            teacher_branch = node["id"] in {"kg_solve", "kg_review"}
            self.assertEqual(data["model"]["provider"], BINDING["provider"])
            self.assertEqual(data["model"]["name"], BINDING["model"])
            self.assertEqual(set(data["model"]["completion_params"]), {"max_tokens"})
            self.assertIn(
                data["model"]["completion_params"]["max_tokens"], (4096, 8192)
            )
            self.assertIs(data["structured_output_switch_on"], False)
            self.assertIsNone(data["memory"])
            self.assertFalse(data["vision"]["enabled"])
            self.assertEqual(
                data["context"], {"enabled": False, "variable_selector": []}
            )
            self.assertEqual(
                data["retry_config"],
                {
                    "retry_enabled": True,
                    "max_retries": 5 if teacher_branch else 2,
                    "retry_interval": 5000 if teacher_branch else 2000,
                },
            )
            self.assertEqual(data["error_strategy"], "default-value")
            self.assertEqual(
                json.loads(data["default_value"][0]["value"])["reason"], "model_failure"
            )
            self.assertIn("JSON", data["prompt_template"][0]["text"])
        for node_id in ("kg_solve", "kg_review"):
            prompts = dump(self.nodes[node_id]["data"]["prompt_template"])
            self.assertIn("{{#kg_evidence.evidence#}}", prompts)
            self.assertNotIn("kg_serialize", prompts)
            self.assertNotIn("conversation", prompts)
        self.assertIn(
            "results.items",
            self.nodes["kg_general"]["data"]["prompt_template"][0]["text"],
        )

    def test_canonical_validation_rejects_scope_filter_model_and_capacity_tampering(
        self,
    ):
        changes = [
            ("kg_solve", "selected", False),
            ("kg_solve", "context", {"enabled": False}),
            (
                "kg_solve",
                "context",
                {"enabled": False, "variable_selector": ["kg_retrieval", "result"]},
            ),
            ("kg_iteration", "parallel_nums", 4),
            ("kg_iteration", "flatten_output", True),
            ("kg_iteration", "error_handle_mode", "remove-abnormal-output"),
            ("kg_iteration", "output_selector", ["kg_solve", "text"]),
            ("kg_retrieval", "metadata_filtering_mode", "disabled"),
            (
                "kg_retrieval",
                "metadata_filtering_conditions",
                {"logical_operator": "or", "conditions": []},
            ),
            ("kg_evidence", "container_id", "different"),
            ("kg_solve", "structured_output_switch_on", True),
            ("kg_review", "memory", {"enabled": True}),
        ]
        for node_id, field, value in changes:
            with self.subTest(node=node_id, field=field):
                dsl = copy.deepcopy(self.dsl)
                node = next(
                    node
                    for node in dsl["workflow"]["graph"]["nodes"]
                    if node["id"] == node_id
                )
                node["data"][field] = value
                with self.assertRaises(ValueError):
                    WORKFLOW.validate_teacher_workflow(dsl)
        for missing in (False, True):
            dsl = copy.deepcopy(self.dsl)
            retrieval = next(
                node
                for node in dsl["workflow"]["graph"]["nodes"]
                if node["id"] == "kg_retrieval"
            )
            conditions = retrieval["data"]["metadata_filtering_conditions"][
                "conditions"
            ]
            if missing:
                conditions[0].pop("id")
            else:
                conditions[1]["id"] = conditions[0]["id"]
            with self.assertRaises(ValueError):
                WORKFLOW.validate_teacher_workflow(dsl)
        for top_k in (0, 4, 31, True):
            with self.subTest(top_k=top_k), self.assertRaises(ValueError):
                WORKFLOW.build_teacher_workflow(
                    SOURCE, REAL_DATA, {**BINDING, "retrieval_top_k": top_k}
                )

    def test_builder_is_deterministic_detached_and_does_not_execute_source(self):
        before = dump(REAL_DATA)
        self.assertEqual(
            self.dsl, WORKFLOW.build_teacher_workflow(SOURCE, REAL_DATA, BINDING)
        )
        WORKFLOW.validate_teacher_workflow(json.loads(dump(self.dsl)))
        WORKFLOW.build_teacher_workflow(
            SOURCE + "\nraise RuntimeError('must not execute during build')\n",
            REAL_DATA,
            BINDING,
        )
        self.assertEqual(dump(REAL_DATA), before)
        self.assertLessEqual(len(json.dumps(self.dsl).encode()), 10 * 1024 * 1024)

    def test_all_seven_code_wrappers_execute_without_models_or_iteration_emulation(
        self,
    ):
        for node in self.nodes.values():
            if node["data"]["type"] == "code":
                self.assertEqual(
                    node["data"]["retry_config"],
                    {"retry_enabled": True, "max_retries": 2, "retry_interval": 1000},
                )

        def run(node_id, **kwargs):
            namespace = {}
            exec(  # noqa: S102 - generated wrappers contain only reviewed local code
                compile(
                    self.nodes[node_id]["data"]["code"],
                    "<trusted-generated-wrapper>",
                    "exec",
                ),
                namespace,
            )
            result = namespace["main"](**kwargs)
            self.assertEqual(set(result), set(self.nodes[node_id]["data"]["outputs"]))
            for value in result.values():
                if isinstance(value, str):
                    self.assertLessEqual(len(value), 80000)
            return result

        prepared = run("kg_prepare", query=SUMMARY_QUESTION, state="")
        selected = run("kg_select", classification=classification(), **prepared)
        extracted = run("kg_extract", item=selected["teachers"][0])
        evidence = run(
            "kg_evidence",
            **extracted,
            result=[native_hit(METHODS[SUMMARY_SKILLS[0]])],
            context=selected["context"],
        )
        verified = run(
            "kg_verify",
            **extracted,
            solution=dump(summary_solution()),
            review=dump(review()),
            **evidence,
            context=selected["context"],
        )
        self.assertEqual(verified["result"]["status"], "answered")
        serialized = run(
            "kg_serialize",
            results=[verified["result"], None],
            context=selected["context"],
        )
        rendered = run(
            "kg_render",
            context=selected["context"],
            **serialized,
            general=dump(abstention()),
            general_review=dump(review()),
        )
        self.assertIn(SUMMARY_ANSWERS[0], rendered["answer"])
        self.assertEqual(json.loads(rendered["state"])["last_teacher_ids"], SUMMARY_IDS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
