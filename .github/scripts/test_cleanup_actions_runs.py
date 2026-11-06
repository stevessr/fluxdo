"""Regression tests for the scheduled Actions run cleanup."""
import importlib.util
from datetime import datetime, timedelta, timezone
from pathlib import Path
import unittest
from unittest.mock import Mock


spec = importlib.util.spec_from_file_location(
    "cleanup_actions_runs", Path(__file__).with_name("cleanup_actions_runs.py")
)
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)

NOW = datetime(2026, 9, 19, tzinfo=timezone.utc)
REPO = "stevessr/fluxdo"
EXISTING = ".github/workflows/build.yaml"
REMOVED = ".github/workflows/old-experiment.yml"


def run(path, age_days, status="completed", branch="main"):
    return {
        "id": 42,
        "path": path,
        "status": status,
        "created_at": (NOW - timedelta(days=age_days)).isoformat(),
        "head_branch": branch,
        "head_repository": {"full_name": REPO},
    }


class CandidateTests(unittest.TestCase):
    def reason(self, candidate, paths=None, branch_exists=False,
               active_days=30, orphan_days=3):
        check = Mock(return_value=branch_exists)
        reason = cleanup.deletion_reason(
            candidate, {EXISTING} if paths is None else paths,
            REPO, check, NOW, active_days, orphan_days
        )
        return reason, check

    def test_old_workflow_runs_are_retained_until_threshold(self):
        self.assertIsNone(self.reason(run(EXISTING, 29))[0])
        self.assertEqual(self.reason(run(EXISTING, 30))[0], "old")

    def test_deleted_yaml_has_shorter_retention(self):
        self.assertIsNone(self.reason(run(REMOVED, 2))[0])
        self.assertEqual(self.reason(run(REMOVED, 3))[0], "orphan")

    def test_branch_only_yaml_is_not_mistaken_for_deleted_yaml(self):
        reason, check = self.reason(run(REMOVED, 4, branch="feature"),
                                    branch_exists=True)
        self.assertIsNone(reason)
        check.assert_called_once_with("feature", REMOVED)
        self.assertEqual(
            self.reason(run(REMOVED, 31, branch="feature"),
                        branch_exists=True)[0], "old"
        )

    def test_in_progress_and_unknown_paths_never_deleted(self):
        self.assertIsNone(self.reason(run(REMOVED, 90, status="in_progress"))[0])
        self.assertIsNone(self.reason(run("other/repo/.github/workflows/a.yml", 90))[0])
        self.assertIsNone(self.reason(run(".github/workflows/../x.yml", 90))[0])

    def test_forked_workflow_not_assumed_to_be_deleted(self):
        candidate = run(REMOVED, 90, branch="feature")
        candidate["head_repository"]["full_name"] = "someone/else"
        reason, check = self.reason(candidate)
        self.assertIsNone(reason)
        check.assert_not_called()

    def test_existing_workflow_does_not_require_branch_lookup(self):
        reason, check = self.reason(run(EXISTING, 90))
        self.assertEqual(reason, "old")
        check.assert_not_called()

    def test_missing_run_timestamp_does_not_delete(self):
        candidate = run(REMOVED, 90)
        candidate["created_at"] = "not-a-date"
        self.assertIsNone(self.reason(candidate)[0])


class APIBehaviorTests(unittest.TestCase):
    def test_branch_results_are_cached(self):
        api = cleanup.GitHubAPI(REPO, "example-token")
        api.request = Mock(return_value={"type": "file"})
        self.assertTrue(api.branch_has_workflow("feature/test", REMOVED))
        self.assertTrue(api.branch_has_workflow("feature/test", REMOVED))
        self.assertEqual(api.request.call_count, 1)

    def test_workflow_directory_failure_is_fail_closed(self):
        api = cleanup.GitHubAPI(REPO, "example-token")
        api.request = Mock(return_value=[])
        with self.assertRaisesRegex(RuntimeError, "refusing to delete"):
            api.current_workflows()

    def test_completed_runs_uses_supported_created_filter(self):
        api = cleanup.GitHubAPI(REPO, "example-token")
        older_run = run(REMOVED, 4)

        def request(path):
            # GitHub Actions silently returns an empty search for
            # created=..TIMESTAMP, even when older runs exist.
            if "created=%3C%3D2026-09-19T00%3A00%3A00Z" in path:
                return {"workflow_runs": [older_run]}
            return {"workflow_runs": []}

        api.request = Mock(side_effect=request)
        self.assertEqual(list(api.completed_runs(NOW)), [older_run])
        api.request.assert_called_once()
        self.assertIn("status=completed", api.request.call_args.args[0])

    def test_paginated_runs_are_not_limited_to_first_page(self):
        api = cleanup.GitHubAPI(REPO, "example-token")
        first = [{"id": i, "created_at": "2026-09-01T00:00:00Z"}
                 for i in range(100)]
        second = [{"id": 101, "created_at": "2026-08-31T00:00:00Z"}]
        api.request = Mock(side_effect=[
            {"workflow_runs": first}, {"workflow_runs": second}
        ])
        found = list(api.completed_runs(NOW))
        self.assertEqual(len(found), 101)
        self.assertEqual(api.request.call_count, 2)


if __name__ == "__main__":
    unittest.main()
