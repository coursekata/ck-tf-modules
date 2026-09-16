"""Exercise the hook's scheduling and failure handling without providers or AWS."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


RUNNER = Path(__file__).resolve().parents[1] / "tofu-test-changed.sh"
FAKE_TOFU = r'''
import fcntl
import json
import os
from pathlib import Path
import sys
import time

state_path = Path(os.environ["FAKE_STATE"])
root = str(Path.cwd().relative_to(os.environ["FAKE_REPO"]))
command = sys.argv[1]

def record(event, delta=0):
    with state_path.open("r+") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        state = json.load(stream)
        state["active"] += delta
        state["peak"] = max(state["peak"], state["active"])
        state["events"].append([root, event, sys.argv[2:]])
        stream.seek(0)
        json.dump(state, stream)
        stream.truncate()

if command == "init":
    record("init")
    if root == os.environ.get("FAIL_INIT"):
        print("fixture initialization failure", file=sys.stderr)
        sys.exit(9)
    Path(".terraform").mkdir(exist_ok=True)
elif command == "test":
    record("start", 1)
    # First pair rendezvous: a serial implementation cannot pass the barrier.
    if os.environ.get("BARRIER") == "1" and root in ("a", "b"):
        marker = state_path.parent / (root + ".started")
        marker.touch()
        other = state_path.parent / (("b" if root == "a" else "a") + ".started")
        deadline = time.monotonic() + 5
        while not other.exists():
            if time.monotonic() > deadline:
                print("workers failed to overlap", file=sys.stderr)
                sys.exit(8)
            time.sleep(0.01)
    time.sleep(0.03)
    print("fixture test output: " + root)
    record("end", -1)
    sys.exit(int(os.environ.get("FAIL_CODE", "7")) if root == os.environ.get("FAIL_TEST") else 0)
else:
    raise AssertionError(command)
'''


class TestRunner(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo"
        self.repo.mkdir()
        self.state = self.base / "state.json"
        self.state.write_text(json.dumps({"active": 0, "peak": 0, "events": []}))
        binary = self.base / "bin" / "tofu"
        binary.parent.mkdir()
        binary.write_text(f"#!{sys.executable}\n" + textwrap.dedent(FAKE_TOFU))
        binary.chmod(0o755)
        self.env = dict(os.environ)
        self.env.pop("TOFU_TEST_JOBS", None)
        self.env.update(
            PATH=str(binary.parent) + os.pathsep + os.environ["PATH"],
            FAKE_STATE=str(self.state),
            FAKE_REPO=str(self.repo),
        )

    def root(self, name):
        path = self.repo / name
        (path / "tests").mkdir(parents=True, exist_ok=True)
        (path / "tests" / "basic.tftest.hcl").touch()
        (path / "main.tf").touch()
        return f"{name}/main.tf"

    def run_hook(self, paths, **env):
        result = subprocess.run(
            ["/bin/bash", str(RUNNER), *paths],
            cwd=self.repo,
            env=self.env | env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        return result, json.loads(self.state.read_text())

    def test_no_selected_suite_is_a_noop(self):
        for paths in ([], ["README.md", "unrelated/main.tf"]):
            result, state = self.run_hook(paths)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state["events"], [])

    def test_deduplicates_roots_and_preserves_spaces(self):
        path = self.root("modules/a module")
        result, state = self.run_hook(
            [path, path, "modules/a module/tests/basic.tftest.hcl"]
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([e[1] for e in state["events"]], ["init", "start", "end"])
        self.assertIn("tofu init: modules/a module passed (", result.stdout)
        self.assertIn("tofu test: modules/a module exit=0 (", result.stdout)

    def test_finds_repository_root_suite(self):
        self.root(".")
        result, state = self.run_hook(["main.tf", "tests/basic.tftest.hcl"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([e[0] for e in state["events"]], [".", ".", "."])

    def test_uses_nearest_suite(self):
        self.root("modules/parent")
        nested = self.root("modules/parent/child")
        result, state = self.run_hook([nested])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({e[0] for e in state["events"]}, {"modules/parent/child"})

    def test_reinitializes_existing_directories_without_backend(self):
        path = self.root("a")
        (self.repo / "a/.terraform").mkdir()
        result, state = self.run_hook([path])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["events"][0], ["a", "init", [
            "-backend=false", "-input=false", "-no-color"
        ]])

    def test_init_failure_fails_hook_but_other_roots_still_run(self):
        paths = [self.root("a"), self.root("b")]
        result, state = self.run_hook(paths, FAIL_INIT="a")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fixture initialization failure", result.stderr)
        self.assertIn("tests could not run", result.stderr)
        self.assertEqual([e[0] for e in state["events"] if e[1] == "start"], ["b"])

    def test_worker_failure_survives_later_success(self):
        paths = [self.root(name) for name in ("a", "b", "c")]
        result, state = self.run_hook(paths, FAIL_TEST="a")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual({e[0] for e in state["events"] if e[1] == "end"}, {"a", "b", "c"})
        self.assertIn("tofu test: a exit=7", result.stdout)
        self.assertIn("fixture test output: c", result.stdout)

    def test_exit_255_does_not_skip_remaining_roots(self):
        paths = [self.root(name) for name in ("a", "b", "c")]
        result, state = self.run_hook(
            paths, FAIL_TEST="a", FAIL_CODE="255", TOFU_TEST_JOBS="1"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual({e[0] for e in state["events"] if e[1] == "end"}, {"a", "b", "c"})
        self.assertIn("tofu test: a exit=255", result.stdout)

    def test_two_workers_overlap_without_exceeding_limit(self):
        paths = [self.root(name) for name in ("a", "b", "c", "d", "e")]
        result, state = self.run_hook(paths, BARRIER="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(state["peak"], 2)
        self.assertEqual(state["active"], 0)
        self.assertEqual([e[1] for e in state["events"][:5]], ["init"] * 5)

    def test_worker_count_can_be_one(self):
        paths = [self.root("a"), self.root("b")]
        result, state = self.run_hook(paths, TOFU_TEST_JOBS="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["peak"], 1)

    def test_rejects_invalid_worker_counts(self):
        path = self.root("a")
        for value in ("0", "-1", "1.5", "no", "01"):
            with self.subTest(value=value):
                result, state = self.run_hook([path], TOFU_TEST_JOBS=value)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("positive integer", result.stderr)
                self.assertEqual(state["events"], [])


if __name__ == "__main__":
    unittest.main()
