#!/usr/bin/python3
"""Tests for bin/agents-usage-claude and bin/agents-usage-update.

The oracle is Omarchy's own collector, /usr/share/omarchy/bin/omarchy-agent-usage-claude:
after every change to a folder of made-up transcripts (lines appended, a line
half written, a resumed session repeating message ids, a transcript deleted,
replaced, cut short or rewritten in place), the incremental scan must print
what Omarchy's full scan prints, while reading only what was appended.
Everything runs in a temporary folder: no real transcript, cache or record
is touched, and nothing reaches the network.

  python3 tests/usage-claude.test.py
"""

import datetime as dt
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True  # loading bin/'s scripts must leave no __pycache__ there
HERE = Path(__file__).resolve().parent
OURS = HERE.parent / "bin" / "agents-usage-claude"
UPDATER = HERE.parent / "bin" / "agents-usage-update"
UPSTREAM = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "bin" / "omarchy-agent-usage-claude"


def load(name, path):
  loader = importlib.machinery.SourceFileLoader(name, str(path))
  spec = importlib.util.spec_from_loader(name, loader)
  module = importlib.util.module_from_spec(spec)
  loader.exec_module(module)
  return module


def stamp(days_ago=0, hour=12):
  day = dt.datetime.now().astimezone().replace(hour=hour, minute=0, second=0, microsecond=0)
  return (day - dt.timedelta(days=days_ago)).isoformat()


def assistant(mid, days_ago=0, model="claude-opus-5-5", tokens=(10, 20, 30, 40), session="s1", uuid=None):
  message = {"role": "assistant", "model": model, "usage": {
    "input_tokens": tokens[0], "output_tokens": tokens[1],
    "cache_read_input_tokens": tokens[2], "cache_creation_input_tokens": tokens[3]}}
  if mid:
    message["id"] = mid
  entry = {"type": "assistant", "sessionId": session, "timestamp": stamp(days_ago), "message": message}
  if uuid:
    entry["uuid"] = uuid
  return json.dumps(entry) + "\n"


def user(text="hello"):
  return json.dumps({"type": "user", "message": {"role": "user", "content": text}}) + "\n"


class IncrementalScan(unittest.TestCase):
  @classmethod
  def setUpClass(cls):
    if not UPSTREAM.exists():
      raise unittest.SkipTest(f"{UPSTREAM} not found: Omarchy's collector is the oracle")
    cls.tmp = Path(tempfile.mkdtemp(prefix="agents-usage-test."))
    os.environ["XDG_CACHE_HOME"] = str(cls.tmp / "cache")
    cls.ours = load("agents_usage_claude", OURS)
    cls.upstream = load("omarchy_agent_usage_claude", UPSTREAM)

  @classmethod
  def tearDownClass(cls):
    shutil.rmtree(cls.tmp, ignore_errors=True)

  def setUp(self):
    self.projects = Path(tempfile.mkdtemp(dir=self.tmp)) / "projects"
    (self.projects / "-home-a").mkdir(parents=True)
    (self.projects / "-home-b" / "s9" / "subagents").mkdir(parents=True)

  def write(self, rel, text, mode="w"):
    path = self.projects / rel
    with open(path, mode, encoding="utf-8") as handle:
      handle.write(text)
    return path

  def check(self, **expect):
    """One incremental pass; it must equal Omarchy's full scan of the folder."""
    stats = {}
    got = self.ours.scan_projects(self.projects, stats_out=stats)
    want = self.upstream.scan_projects(self.projects)
    self.assertEqual(json.dumps(got, sort_keys=True), json.dumps(want, sort_keys=True))
    for key, value in expect.items():
      self.assertEqual(stats[key], value, f"{key} in {stats}")
    return stats

  def base(self):
    a = self.write("-home-a/s1.jsonl", "".join([
      user(),
      assistant("msg_1"),
      assistant("msg_1"),  # the same message's next content block: counted once
      assistant("msg_2", days_ago=3, model="claude-sonnet-5-5"),
      assistant("msg_3", days_ago=40),
      assistant("msg_z", tokens=(0, 0, 0, 0)),  # claims msg_z with no tokens...
      assistant("msg_z", tokens=(5, 5, 5, 5)),  # ...so upstream skips this one
      assistant(None, uuid="u-1"),  # no message id: keyed by file and uuid
      assistant(None),  # nor uuid: keyed by file and line number
      "not json but \"usage\": here\n",
      json.dumps({"type": "user", "usage": {"input_tokens": 99}}) + "\n",
    ]))
    b = self.write("-home-b/s9/subagents/agent-1.jsonl", assistant("msg_9", session="s9", days_ago=1))
    return a, b

  def test_first_pass_and_nothing_new(self):
    self.base()
    self.check(read=2)
    self.check(read=0, bytes=0)

  def test_append_reads_only_the_new_bytes(self):
    a, _ = self.base()
    self.check()
    line = assistant("msg_4", model="claude-haiku-5-5")
    self.write("-home-a/s1.jsonl", line, "a")
    stats = self.check(read=1)
    # The new line, and the few bytes before it that show the file is the same.
    self.assertLessEqual(stats["bytes"], len(line.encode()) + self.ours.TAIL_BYTES)

  def test_line_half_written(self):
    self.base()
    self.check()
    line = assistant("msg_5")
    self.write("-home-a/s1.jsonl", line[:40], "a")
    self.check()
    self.write("-home-a/s1.jsonl", line[40:], "a")
    self.check()
    # Line numbers keep counting across passes: a key without id or uuid is
    # its line number, and must not collide with an earlier line's.
    self.write("-home-a/s1.jsonl", assistant(None) + assistant(None), "a")
    self.check()

  def test_resumed_session_then_original_deleted(self):
    a, _ = self.base()
    self.check()
    # A resumed session repeats the earlier messages, then adds its own.
    self.write("-home-a/s2.jsonl", assistant("msg_1") + assistant("msg_2", days_ago=3, model="claude-sonnet-5-5")
               + assistant("msg_6", session="s2"))
    self.check(read=1)
    a.unlink()
    stats = self.check(gone=1)
    self.assertEqual(stats["read"], 0)

  def test_replaced_by_another_file(self):
    self.base()
    self.check()
    fresh = self.write("-home-a/new.tmp", assistant("msg_7") + assistant("msg_8", days_ago=2))
    fresh.replace(self.projects / "-home-a" / "s1.jsonl")
    self.check(reset=1)

  def test_cut_short(self):
    a, _ = self.base()
    self.check()
    with open(a, "w", encoding="utf-8") as handle:
      handle.write(assistant("msg_2", days_ago=3, model="claude-sonnet-5-5"))
    self.check(reset=1)

  def test_rewritten_in_place_and_longer(self):
    # The same inode, no shorter, other text where the last pass stopped. (A
    # change only further back than TAIL_BYTES goes unseen: transcripts are
    # only appended to; --rebuild reads everything again.)
    a, _ = self.base()
    self.check()
    size = a.stat().st_size
    text = "".join(assistant(f"msg_r{i}", days_ago=i % 5, model="claude-sonnet-5-5") for i in range(12))
    self.assertGreater(len(text), size)
    with open(a, "w", encoding="utf-8") as handle:
      handle.write(text)
    self.check(reset=1)

  def test_rebuild(self):
    self.base()
    self.check()
    got = self.ours.scan_projects(self.projects, rebuild=True)
    self.assertEqual(json.dumps(got, sort_keys=True),
                     json.dumps(self.upstream.scan_projects(self.projects), sort_keys=True))

  def test_no_folder(self):
    shutil.rmtree(self.projects)
    self.check(files=0)


class Updater(unittest.TestCase):
  """agents-usage-update hands the other agents to Omarchy's updater, with the
  arguments it was given, and writes Claude's record itself."""

  def setUp(self):
    self.tmp = Path(tempfile.mkdtemp(prefix="agents-usage-update-test."))
    stub_dir = self.tmp / "bin"
    stub_dir.mkdir()
    self.log = self.tmp / "omarchy.log"
    stub = stub_dir / "omarchy-agent-usage-update"
    stub.write_text(f'#!/bin/sh\necho "$*" >> "{self.log}"\n')
    stub.chmod(0o755)
    (self.tmp / "claude" / "projects" / "-p").mkdir(parents=True)
    (self.tmp / "claude" / "projects" / "-p" / "s.jsonl").write_text(assistant("msg_1"))
    self.env = dict(os.environ, PATH=f"{stub_dir}:{os.environ['PATH']}",
                    XDG_STATE_HOME=str(self.tmp / "state"), XDG_CACHE_HOME=str(self.tmp / "cache"),
                    CLAUDE_CONFIG_DIR=str(self.tmp / "claude"))
    self.record = self.tmp / "state" / "omarchy" / "agents" / "usage" / "claude.json"

  def tearDown(self):
    shutil.rmtree(self.tmp, ignore_errors=True)

  def run_update(self, *args):
    done = subprocess.run([str(UPDATER), *args], env=self.env, capture_output=True, text=True, timeout=60)
    self.assertEqual(done.returncode, 0, done.stderr)
    return self.log.read_text().splitlines() if self.log.exists() else []

  def test_every_agent(self):
    self.assertEqual(self.run_update(), ["--except claude"])
    record = json.loads(self.record.read_text())
    self.assertEqual(record["id"], "claude")
    self.assertEqual(record["totalPrompts"], 1)
    self.assertEqual(record["usageStatusText"], "Waiting for auth")

  def test_claude_alone(self):
    self.assertEqual(self.run_update("--limits-only", "claude"), [])
    self.assertTrue(self.record.exists())

  def test_claude_disabled(self):
    self.assertEqual(self.run_update("--force", "--except", "claude", "--except", "codex"),
                     ["--force --except claude --except codex --except claude"])
    self.assertFalse(self.record.exists())

  def test_others_named(self):
    self.assertEqual(self.run_update("--limits-only", "codex", "claude"), ["--limits-only --except claude codex"])
    self.assertTrue(self.record.exists())


if __name__ == "__main__":
  unittest.main(verbosity=2)
