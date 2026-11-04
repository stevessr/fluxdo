#!/usr/bin/env python3
"""Clean up completed GitHub Actions runs without deleting active builds.

Scheduled runs delete old history for current workflows and shorter-lived history
for workflows whose YAML no longer exists on the default branch. Branch-only
workflows are checked before classifying their runs as orphaned.
"""

import argparse
from datetime import datetime, timedelta, timezone
import json
import os
import re
import sys
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


WORKFLOW_PATH = re.compile(r"^\.github/workflows/[^/]+\.ya?ml$")


def parse_timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


class GitHubAPI:
    def __init__(self, repository, token):
        self.repository = repository
        self.token = token
        self.branch_cache = {}

    def request(self, path, method="GET", allow_missing=False):
        url = f"https://api.github.com/repos/{self.repository}/{path}"
        request = Request(
            url,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "fluxdo-actions-run-cleanup",
            },
        )
        try:
            with urlopen(request, timeout=30) as response:
                body = response.read()
                return json.loads(body) if body else None
        except HTTPError as error:
            if allow_missing and error.code == 404:
                return None
            raise RuntimeError(
                f"GitHub API {method} {path}: HTTP {error.code}"
            ) from error

    def current_workflows(self):
        entries = self.request("contents/.github/workflows")
        if not isinstance(entries, list):
            raise RuntimeError("Cannot verify current workflows: expected directory listing")
        paths = {
            entry["path"]
            for entry in entries
            if entry.get("type") == "file"
            and WORKFLOW_PATH.fullmatch(entry.get("path", ""))
        }
        if not paths:
            raise RuntimeError("No current workflow files returned; refusing to delete runs")
        return paths

    def branch_has_workflow(self, branch, path):
        key = (branch, path)
        if key not in self.branch_cache:
            params = urlencode({"ref": branch})
            safe_path = quote(path, safe="/")
            data = self.request(
                f"contents/{safe_path}?{params}", allow_missing=True
            )
            self.branch_cache[key] = bool(
                isinstance(data, dict) and data.get("type") == "file"
            )
        return self.branch_cache[key]

    def completed_runs(self, cutoff):
        # GitHub limits filtered run searches to 1,000 results. The Actions
        # runs endpoint does not support an open-ended "..timestamp" range:
        # it silently returns zero runs. Use the supported <=timestamp filter
        # and resume with an inclusive boundary, deduplicating overlapping runs.
        upper = cutoff.strftime("%Y-%m-%dT%H:%M:%SZ")
        seen = set()
        previous_boundary = None
        while True:
            oldest = None
            for page in range(1, 11):
                params = urlencode(
                    {"status": "completed", "created": f"<={upper}",
                     "per_page": 100, "page": page}
                )
                payload = self.request(f"actions/runs?{params}")
                runs = payload.get("workflow_runs") if isinstance(payload, dict) else None
                if not isinstance(runs, list):
                    raise RuntimeError("Cannot list workflow runs safely")
                for run in runs:
                    run_id = run.get("id")
                    if run_id is None:
                        continue
                    if run_id not in seen:
                        seen.add(run_id)
                        yield run
                if len(runs) < 100:
                    return
                oldest = runs[-1].get("created_at")
            if not oldest:
                return
            if oldest == previous_boundary:
                raise RuntimeError("Cannot paginate runs beyond the timestamp boundary")
            previous_boundary = oldest
            upper = oldest

    def delete_run(self, run_id):
        self.request(f"actions/runs/{run_id}", method="DELETE", allow_missing=True)


def deletion_reason(run, workflows, repository, branch_has_workflow,
                    now, active_days, orphan_days):
    if run.get("status") != "completed":
        return None
    path = run.get("path", "")
    if not WORKFLOW_PATH.fullmatch(path):
        return None
    try:
        created = parse_timestamp(run["created_at"])
    except (KeyError, ValueError, TypeError):
        return None
    age = now - created
    if age < timedelta(days=orphan_days):
        return None

    exists = path in workflows
    if not exists:
        source = run.get("head_repository") or {}
        # Do not treat a workflow from another repository as a deleted local file.
        if source.get("full_name") not in (None, repository):
            return None
        branch = run.get("head_branch")
        if branch:
            exists = branch_has_workflow(branch, path)

    if exists:
        return "old" if age >= timedelta(days=active_days) else None
    return "orphan"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--active-days", type=int, default=30,
                        help="Retention for workflows that still exist (default: 30)")
    parser.add_argument("--orphan-days", type=int, default=3,
                        help="Retention for removed workflow YAML files (default: 3)")
    parser.add_argument("--max-deletes", type=int, default=400,
                        help="Maximum runs to process per execution (default: 400)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Log candidates without deleting anything")
    args = parser.parse_args(argv)
    if args.active_days < 1 or args.orphan_days < 1 or not 1 <= args.max_deletes <= 1000:
        parser.error("days must be >= 1, and max-deletes must be between 1 and 1000")

    repository = os.environ.get("GITHUB_REPOSITORY", "")
    token = os.environ.get("GITHUB_TOKEN", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or not token:
        parser.error("GITHUB_REPOSITORY and GITHUB_TOKEN are required")

    api = GitHubAPI(repository, token)
    workflows = api.current_workflows()
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=args.orphan_days)
    candidates = []
    scanned = 0
    for run in api.completed_runs(cutoff):
        scanned += 1
        reason = deletion_reason(
            run, workflows, repository, api.branch_has_workflow,
            now, args.active_days, args.orphan_days
        )
        if reason:
            candidates.append((run["id"], run["path"], reason))
            if len(candidates) >= args.max_deletes:
                break

    print(
        f"Current YAML files: {len(workflows)}; inspected completed runs: {scanned}; "
        f"candidates: {len(candidates)}; dry-run: {args.dry_run}",
        flush=True,
    )
    deleted = failed = 0
    for run_id, path, reason in candidates:
        print(f"{'WOULD DELETE' if args.dry_run else 'DELETE'} "
              f"run={run_id} reason={reason} workflow={path}", flush=True)
        if args.dry_run:
            continue
        try:
            api.delete_run(run_id)
            deleted += 1
        except RuntimeError as error:
            failed += 1
            print(f"FAILED run={run_id}: {error}", file=sys.stderr, flush=True)
    print(f"Finished: deleted={deleted}, failed={failed}, "
          f"candidates={len(candidates)}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
