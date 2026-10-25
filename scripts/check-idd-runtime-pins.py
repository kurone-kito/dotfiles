#!/usr/bin/env python3
"""Check that the user-global IDD distribution sources agree (dotfiles #688).

Compares the checked-in inventory `.github/idd/user-global-source.json` with
the chezmoi source under a source root (the repository root by default):

- the selected payload and the two skill trees: the file set and each
  file's SHA-256 digest must match the inventory exactly;
- the selected payload pointer (`symlink_current`) and the Windows
  `current` pointer version;
- every `executable_idd-*` wrapper: each pinned idd-skill commit and each
  40-character commit token must be the inventory commit, and a launcher
  that calls `npx` must carry the exact package spec;
- the versioned harness-entry references;
- the repository's own `iddVersion` and `helperRuntime.packageSpec`.

The check is read-only. It never reads the operator's home directory, runs
a helper, fetches a package, or writes a file. Symbolic links are refused
wherever they would let a read leave the source root or where a scope
would otherwise be incomplete.

Usage: python3 -I scripts/check-idd-runtime-pins.py [--source-root DIR]

Exit status: 0 when every check passes; 1 when a check fails (each problem
is printed as `FAIL <path>: <reason>`); 2 for a usage error.
"""

import argparse
import hashlib
import json
import os
import re
import sys

INVENTORY = '.github/idd/user-global-source.json'
REPO_CONFIG = '.github/idd/config.json'
POINTER = 'home/dot_local/share/idd-skill/symlink_current'
WINDOWS_POINTER = 'home/run_after_83-link-idd-skill-xdg-data.ps1'
WRAPPER_DIR = 'home/dot_local/bin'
WRAPPER_PREFIX = 'executable_idd-'
HARNESS_ENTRIES = {
  'home/dot_claude/CLAUDE.md.tmpl': 'current',
  'home/dot_codex/AGENTS.md.tmpl': 'versioned',
  'home/dot_config/opencode/AGENTS.md.tmpl': 'versioned',
  'home/dot_copilot/copilot-instructions.md.tmpl': 'versioned',
  'home/dot_gemini/GEMINI.md.tmpl': 'versioned',
}
# The scopes the inventory must carry, each with the source and installed root
# it must name. {release} is the inventory release.
EXPECTED_SCOPES = {
  'payload': ('home/dot_local/share/idd-skill/{release}',
              '.local/share/idd-skill/{release}'),
  'skills-claude': ('home/dot_claude/skills', '.claude/skills'),
  'skills-agents': ('home/dot_agents/skills', '.agents/skills'),
}
# Every launcher this repository ships. A missing or extra wrapper fails.
EXPECTED_WRAPPERS = frozenset(
  WRAPPER_PREFIX + name + suffix
  for name in ('activation', 'critique-telemetry', 'critique-telemetry-report',
               'effective-config')
  for suffix in ('', '.cmd', '.ps1'))

SEMVER = re.compile(r'^[0-9]+\.[0-9]+\.[0-9]+$')
SHA1_HEX = re.compile(r'^[0-9a-f]{40}$')
SHA256_HEX = re.compile(r'^[0-9a-f]{64}$')
COMMIT_TOKEN = re.compile(r'(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])')
SPEC_PIN = re.compile(r'kurone-kito/idd-skill/tar\.gz/([0-9A-Za-z]+)')
VERSION_PATH = re.compile(r'idd-skill/([0-9]+\.[0-9]+\.[0-9]+)(?![0-9]|\.[0-9])')
PS_VERSION = re.compile(r"^\$version\s*=\s*'([^']*)'\s*$", re.MULTILINE)


# An npx command in command position: at the start of a line, or after exec,
# &, &&, |, ||, ;, then, do, else, or $(. Guards such as `command -v npx` and
# `Get-Command npx` are not in command position.
NPX_LAUNCH = re.compile(
  r'(?:^\s*|exec\s+|&&?\s*|\|\|?\s*|;\s*|\bthen\s+|\bdo\s+|\belse\s+|\$\(\s*)npx\s')
COMMENT_LINE = re.compile(r'^\s*(#|REM\b|::|//)', re.IGNORECASE)
INLINE_COMMENT = re.compile(r'\s#')


class Problems:
  def __init__(self):
    self.items = []

  def add(self, path, reason):
    self.items.append((path, reason))


def safe_rel(path):
  """True for a relative POSIX path with no empty, dot, or parent parts."""
  if not isinstance(path, str) or not path or '\x00' in path or '\\' in path:
    return False
  if path.startswith('/') or re.match(r'^[A-Za-z]:', path):
    return False
  return all(part not in ('', '.', '..') for part in path.split('/'))


def chezmoi_name(rel):
  """Map an installed relative path to its chezmoi source spelling."""
  return '/'.join(
    ('dot_' + part[1:]) if part.startswith('.') else part
    for part in rel.split('/'))


def read_regular(root, rel, problems):
  """Return the bytes of a regular file under root, or None on failure."""
  current = root
  for part in rel.split('/'):
    current = os.path.join(current, part)
    if is_link(current):
      problems.add(rel, 'symbolic link is not allowed in the source tree')
      return None
  if not os.path.isfile(current):
    problems.add(rel, 'missing from the source tree')
    return None
  with open(current, 'rb') as handle:
    return handle.read()


def digest(data):
  return hashlib.sha256(data).hexdigest()


def load_inventory(root, problems):
  data = read_regular(root, INVENTORY, problems)
  if data is None:
    return None
  try:
    inventory = json.loads(data.decode('utf-8'))
  except (UnicodeDecodeError, ValueError) as error:
    problems.add(INVENTORY, 'malformed JSON: %s' % error)
    return None
  if not isinstance(inventory, dict) or inventory.get('schemaVersion') != 1:
    problems.add(INVENTORY, 'schemaVersion must be 1')
    return None
  release = inventory.get('release')
  upstream = inventory.get('upstream')
  if not isinstance(release, str) or not SEMVER.match(release):
    problems.add(INVENTORY, 'release must be an X.Y.Z version')
    return None
  if not isinstance(upstream, dict):
    problems.add(INVENTORY, 'upstream must be an object')
    return None
  commit = upstream.get('commit')
  if not isinstance(commit, str) or not SHA1_HEX.match(commit):
    problems.add(INVENTORY, 'upstream.commit must be a 40-character lowercase hex commit')
    return None
  archive = upstream.get('archiveSha256')
  if not isinstance(archive, str) or not SHA256_HEX.match(archive):
    problems.add(INVENTORY, 'upstream.archiveSha256 must be a SHA-256 hex digest')
  if upstream.get('repository') != 'kurone-kito/idd-skill':
    problems.add(INVENTORY, 'upstream.repository must be kurone-kito/idd-skill')
    return None
  if upstream.get('tag') != 'v' + release:
    problems.add(INVENTORY, 'upstream.tag must be v%s' % release)
    return None
  tag_object = upstream.get('tagObject')
  if not isinstance(tag_object, str) or not SHA1_HEX.match(tag_object):
    problems.add(INVENTORY, 'upstream.tagObject must be a 40-character lowercase hex id')
    return None
  expected_spec = 'https://codeload.github.com/kurone-kito/idd-skill/tar.gz/' + commit
  if upstream.get('packageSpec') != expected_spec:
    problems.add(INVENTORY, 'upstream.packageSpec must be the codeload URL of upstream.commit')
    return None
  scopes = inventory.get('scopes')
  if not isinstance(scopes, list) or not scopes:
    problems.add(INVENTORY, 'scopes must be a non-empty list')
    return None
  seen = set()
  for scope in scopes:
    if not isinstance(scope, dict) or not isinstance(scope.get('id'), str):
      problems.add(INVENTORY, 'every scope needs a string id')
      return None
    if scope['id'] in seen:
      problems.add(INVENTORY, 'duplicate scope id %s' % scope['id'])
      return None
    seen.add(scope['id'])
    expected_roots = EXPECTED_SCOPES.get(scope['id'])
    if expected_roots is None:
      problems.add(INVENTORY, 'unexpected scope id %s' % scope['id'])
      return None
    wanted = [root.format(release=release) for root in expected_roots]
    if [scope.get('sourceRoot'), scope.get('installedRoot')] != wanted:
      problems.add(INVENTORY, 'scope %s must name %s and %s'
                   % (scope['id'], wanted[0], wanted[1]))
      return None
    for key in ('sourceRoot', 'installedRoot'):
      if not safe_rel(scope.get(key)):
        problems.add(INVENTORY, 'scope %s has an unsafe %s' % (scope['id'], key))
        return None
    files = scope.get('files')
    if not isinstance(files, dict) or not files:
      problems.add(INVENTORY, 'scope %s needs a non-empty files object' % scope['id'])
      return None
    for rel, value in files.items():
      if not safe_rel(rel):
        problems.add(INVENTORY, 'scope %s has an unsafe path: %r' % (scope['id'], rel))
        return None
      if not isinstance(value, str) or not SHA256_HEX.match(value):
        problems.add(INVENTORY, 'scope %s digest for %s is not SHA-256' % (scope['id'], rel))
        return None
  if seen != set(EXPECTED_SCOPES):
    problems.add(INVENTORY, 'inventory must carry exactly the scopes %s'
                 % ', '.join(sorted(EXPECTED_SCOPES)))
    return None
  return inventory


REPARSE_POINT = 0x400


def is_link(path):
  """True for a symbolic link, a directory junction, or any reparse point."""
  if os.path.islink(path):
    return True
  try:
    info = os.lstat(path)
  except OSError:
    return False
  # Windows junctions carry the reparse-point attribute, not a link flag.
  return bool(getattr(info, 'st_file_attributes', 0) & REPARSE_POINT)


def path_has_symlink(root, rel):
  """True when any component of rel, below root, is a link or reparse point."""
  current = root
  for part in rel.split('/'):
    current = os.path.join(current, part)
    if is_link(current):
      return True
  return False


def walk_scope(root, source_root, problems):
  """Return {relative path: absolute path} for regular files under a scope."""
  top = os.path.join(root, *source_root.split('/'))
  if path_has_symlink(root, source_root) or not os.path.isdir(top):
    problems.add(source_root, 'scope source root is missing or not a directory')
    return None
  found = {}
  for current, dirs, files in os.walk(top, followlinks=False):
    for name in dirs + files:
      full = os.path.join(current, name)
      rel = os.path.relpath(full, top).replace(os.sep, '/')
      if is_link(full):
        problems.add('%s/%s' % (source_root, rel), 'symbolic link is not allowed in a scope')
      elif os.path.isfile(full):
        found[rel] = full
    # Do not descend into a link or junction: its target lies outside the scope.
    dirs[:] = [name for name in dirs if not is_link(os.path.join(current, name))]
  return found


def check_scope(root, scope, problems):
  source_root = scope['sourceRoot']
  # Inventory keys are installed paths; compare them in chezmoi source spelling.
  listed = {}
  for rel, value in scope['files'].items():
    name = chezmoi_name(rel)
    if name in listed:
      problems.add('%s/%s' % (source_root, name),
                   'two inventory paths map to this source path')
      return 0
    listed[name] = value
  actual = walk_scope(root, source_root, problems)
  if actual is None:
    return 0
  for rel in sorted(set(listed) - set(actual)):
    problems.add('%s/%s' % (source_root, rel),
                 'listed in the inventory but missing from the source')
  for rel in sorted(set(actual) - set(listed)):
    problems.add('%s/%s' % (source_root, rel),
                 'unlisted scoped file: not in the inventory')
  for rel in sorted(set(listed) & set(actual)):
    path = '%s/%s' % (source_root, rel)
    data = read_regular(root, path, problems)
    if data is not None and digest(data) != listed[rel]:
      problems.add(path, 'digest differs from the inventory (scope %s)' % scope['id'])
  return len(listed)


def check_pointer(root, release, problems):
  data = read_regular(root, POINTER, problems)
  if data is None:
    return
  value = data.decode('utf-8', 'replace').strip()
  if value != release:
    problems.add(POINTER, 'selected payload pointer names %r, expected %s' % (value, release))


def check_windows_pointer(root, release, problems):
  data = read_regular(root, WINDOWS_POINTER, problems)
  if data is None:
    return
  matches = PS_VERSION.findall(data.decode('utf-8', 'replace'))
  if len(matches) != 1:
    problems.add(WINDOWS_POINTER, 'expected exactly one $version assignment, found %d' % len(matches))
  elif matches[0] != release:
    problems.add(WINDOWS_POINTER, 'Windows current-pointer version is %r, expected %s' % (matches[0], release))


def check_wrappers(root, commit, spec, problems):
  top = os.path.join(root, *WRAPPER_DIR.split('/'))
  if path_has_symlink(root, WRAPPER_DIR) or not os.path.isdir(top):
    problems.add(WRAPPER_DIR, 'wrapper directory is missing or not a directory')
    return 0
  present = {name for name in os.listdir(top) if name.startswith(WRAPPER_PREFIX)}
  for name in sorted(EXPECTED_WRAPPERS - present):
    problems.add('%s/%s' % (WRAPPER_DIR, name), 'expected wrapper is missing')
  for name in sorted(present - EXPECTED_WRAPPERS):
    problems.add('%s/%s' % (WRAPPER_DIR, name),
                 'unlisted wrapper: not an expected launcher')
  count = 0
  for name in sorted(present):
    rel = '%s/%s' % (WRAPPER_DIR, name)
    data = read_regular(root, rel, problems)
    if data is None:
      continue
    count += 1
    text = data.decode('utf-8', 'replace')
    for match in SPEC_PIN.finditer(text):
      if match.group(1) != commit:
        problems.add(rel, 'pins idd-skill commit %s, expected %s' % (match.group(1), commit))
    for token in set(COMMIT_TOKEN.findall(text)):
      if token != commit:
        problems.add(rel, 'mentions commit %s, expected %s' % (token, commit))
    # Every npx launch must pass the exact spec as the --package argument of
    # the code before any inline comment, so neither a comment nor another
    # package can stand in for it. Guards such as `command -v npx` are skipped.
    package_arg = re.compile(
      r'(?:--package(?:\s+|=)|-p\s+)["\']?%s["\']?(?=\s|$)' % re.escape(spec))
    for line in text.splitlines():
      if COMMENT_LINE.match(line):
        continue
      code = INLINE_COMMENT.split(line, 1)[0]
      if not NPX_LAUNCH.search(code) or package_arg.search(code):
        continue
      problems.add(rel, 'npx launch does not pass the exact package spec %s to --package' % spec)
      break
  return count


def check_harness_entries(root, release, problems):
  expected = {
    'current': '.local/share/idd-skill/current/user-global/entry.md',
    'versioned': 'dot_local/share/idd-skill/%s/user-global/entry.md' % release,
  }
  for rel, kind in sorted(HARNESS_ENTRIES.items()):
    data = read_regular(root, rel, problems)
    if data is None:
      continue
    text = data.decode('utf-8', 'replace')
    for version in set(VERSION_PATH.findall(text)):
      if version != release:
        problems.add(rel, 'harness entry names version %s, expected %s' % (version, release))
    if expected[kind] not in text:
      problems.add(rel, 'harness entry does not reference %s' % expected[kind])


def check_repo_config(root, release, spec, problems):
  data = read_regular(root, REPO_CONFIG, problems)
  if data is None:
    return
  try:
    config = json.loads(data.decode('utf-8'))
  except (UnicodeDecodeError, ValueError) as error:
    problems.add(REPO_CONFIG, 'malformed JSON: %s' % error)
    return
  if not isinstance(config, dict):
    problems.add(REPO_CONFIG, 'config must be a JSON object')
    return
  if config.get('iddVersion') != release:
    problems.add(REPO_CONFIG, 'iddVersion is %r, expected %s' % (config.get('iddVersion'), release))
  runtime = config.get('helperRuntime')
  if not isinstance(runtime, dict):
    problems.add(REPO_CONFIG, 'helperRuntime must be a JSON object')
    return
  if runtime.get('packageSpec') != spec:
    problems.add(REPO_CONFIG, 'helperRuntime.packageSpec does not match the inventory commit')


def run(root):
  problems = Problems()
  inventory = load_inventory(root, problems)
  if inventory is None:
    return problems, None
  release = inventory['release']
  upstream = inventory['upstream']
  total = 0
  for scope in inventory['scopes']:
    total += check_scope(root, scope, problems)
  check_pointer(root, release, problems)
  check_windows_pointer(root, release, problems)
  wrappers = check_wrappers(root, upstream['commit'], upstream['packageSpec'], problems)
  check_harness_entries(root, release, problems)
  check_repo_config(root, release, upstream['packageSpec'], problems)
  summary = {
    'release': release,
    'commit': upstream['commit'],
    'scopedFiles': total,
    'wrappers': wrappers,
  }
  return problems, summary


def main(argv):
  parser = argparse.ArgumentParser(
    description='Check user-global IDD distribution source consistency.')
  default_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
  parser.add_argument('--source-root', default=default_root,
                      help='repository or fixture root to check (default: this checkout)')
  # argparse exits 0 for --help and 2 for a usage error, and that status is
  # the one this process reports.
  args = parser.parse_args(argv)
  root = os.path.abspath(args.source_root)
  if not os.path.isdir(root):
    sys.stderr.write('check-idd-runtime-pins: source root is not a directory: %s\n' % root)
    return 2
  problems, summary = run(root)
  for path, reason in problems.items:
    sys.stdout.write('FAIL %s: %s\n' % (path, reason))
  if problems.items:
    sys.stdout.write('idd-runtime-pins: %d problem(s)\n' % len(problems.items))
    return 1
  sys.stdout.write(
    'idd-runtime-pins: consistent (release %s, commit %s, %d scoped files, %d wrappers)\n'
    % (summary['release'], summary['commit'], summary['scopedFiles'], summary['wrappers']))
  return 0


if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
