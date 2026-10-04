#!/usr/bin/env bats
# Regression guard for issue #566's requirement that every live IDD
# workflow helper invocation uses the archive pin in .github/idd/config.json.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
}

check_workflow_helper_pins() {
  python3 - "$REPO_ROOT" <<'PY'
import json
import os
import re
import sys

root = sys.argv[1]
with open(os.path.join(root, ".github/idd/config.json"), encoding="utf-8") as f:
    config = json.load(f)
expected_pin = config["helperRuntime"]["packageSpec"]

expected_counts = {
    ".github/workflows/post-merge-cleanup.yml": 1,
    ".github/workflows/idd-advisory-convergence.yml": 2,
    ".github/workflows/idd-advisory-convergence-comment.yml": 3,
}
package_pattern = re.compile(
    r"(?:^|\s)(?:--package|-p)(?:\s+|=)"
    r"(?:'([^']+)'|\"([^\"]+)\"|([^\s]+))"
)

def split_shell_commands(text):
    commands = []
    command = []
    quote = None
    escaped = False
    at_word_start = True
    index = 0
    while index < len(text):
        char = text[index]
        if escaped:
            command.append(char)
            escaped = False
            at_word_start = False
            index += 1
            continue
        if char == "\\" and quote != "'":
            command.append(char)
            escaped = True
            at_word_start = False
            index += 1
            continue
        if quote:
            command.append(char)
            if char == quote:
                quote = None
            index += 1
            continue
        if char in ("'", '\"'):
            command.append(char)
            quote = char
            at_word_start = False
            index += 1
            continue
        if char == "#" and at_word_start:
            while index < len(text) and text[index] not in "\r\n":
                index += 1
            continue
        if char in "\r\n;|&":
            if command:
                commands.append("".join(command))
                command = []
            if char in ";|&":
                while index + 1 < len(text) and text[index + 1] in ";|&":
                    index += 1
            at_word_start = True
            index += 1
            continue
        command.append(char)
        at_word_start = char.isspace()
        index += 1
    if command:
        commands.append("".join(command))
    return commands

assert split_shell_commands(
    'npx --package=expected # --package=comment\n'
    'npx --package="value; # kept" && npx --package=next'
) == [
    "npx --package=expected ",
    'npx --package="value; # kept" ',
    " npx --package=next",
]
assert split_shell_commands(
    'printf "npx --package=quoted; # content"; npx --package=active'
) == [
    'printf "npx --package=quoted; # content"',
    " npx --package=active",
]
assert split_shell_commands(
    "(npx --package=first; npx --package=second)"
) == [
    "(npx --package=first",
    " npx --package=second)",
]

def npx_invocations(script):
    script = re.sub(r"\\\r?\n[ \t]*", " ", script)
    invocations = []
    for command in split_shell_commands(script):
        candidate = command.lstrip()
        while candidate:
            control = re.match(r"(?:if|then|else|elif|while|until|do)\b\s+", candidate)
            if control:
                candidate = candidate[control.end():]
                continue
            if candidate.startswith("! "):
                candidate = candidate[2:].lstrip()
                continue
            assignment = re.match(
                r"[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|\"(?:\\.|[^\"])*\"|[^\s]*)\s+",
                candidate,
            )
            if assignment:
                candidate = candidate[assignment.end():]
                continue
            break
        match = re.search(r"\bnpx\b([^\n]*)", command) if re.match(
            r"npx\b", candidate
        ) else None
        if not match:
            match = re.search(r"\$\(\s*npx\b([^\n]*)", command)
        if match:
            invocations.append(match.group(1))
    return invocations

assert npx_invocations(
    'npx --package=expected # --package=comment\n'
    'npx --package="value; # kept" && npx --package=next'
) == [
    " --package=expected ",
    ' --package="value; # kept" ',
    " --package=next",
]
assert npx_invocations(
    'echo "npx --package=argument"; JSON=$(npx --package=command helper)'
) == [" --package=command helper)"]
assert npx_invocations("FOO=bar npx --package=assigned helper") == [
    " --package=assigned helper"
]
assert npx_invocations(
    "if condition; then npx --package=conditional helper; fi"
) == [" --package=conditional helper"]

def workflow_run_scripts(workflow):
    lines = workflow.splitlines()
    scripts = []
    index = 0
    while index < len(lines):
        match = re.match(r"^(\s*)(?:-\s*)?run:\s*(.*?)\s*$", lines[index])
        if not match:
            index += 1
            continue
        parent_indent = len(match.group(1))
        value = match.group(2).split("#", 1)[0].strip()
        if re.fullmatch(r"[|>][+-]?[0-9]?[+-]?", value):
            block = []
            index += 1
            while index < len(lines):
                line = lines[index]
                indentation = len(line) - len(line.lstrip(" "))
                if line.strip() and indentation <= parent_indent:
                    break
                block.append(line)
                index += 1
            indents = [
                len(line) - len(line.lstrip(" "))
                for line in block if line.strip()
            ]
            content_indent = min(indents) if indents else parent_indent
            scripts.append("\n".join(
                line[content_indent:] if line.strip() else "" for line in block
            ))
        else:
            scripts.append(value)
            index += 1
    return scripts

assert workflow_run_scripts(
    "steps:\n  - name: Example\n    run: |\n      echo npx --package=comment\n"
    "      npx --package=command\n  - name: Next\n    run: echo done\n"
) == [
    "echo npx --package=comment\nnpx --package=command",
    "echo done",
]
total = 0
for relative_path, expected_count in expected_counts.items():
    with open(os.path.join(root, relative_path), encoding="utf-8") as f:
        workflow = f.read()
    invocations = [
        invocation
        for script in workflow_run_scripts(workflow)
        for invocation in npx_invocations(script)
    ]
    assert len(invocations) == expected_count, (
        f"{relative_path}: expected {expected_count} active helper invocations, "
        f"found {len(invocations)}"
    )
    for invocation in invocations:
        matches = package_pattern.findall(invocation)
        pins = [next(value for value in match if value) for match in matches]
        assert len(pins) == 1, (
            f"{relative_path}: expected one package pin in {invocation!r}, "
            f"found {pins!r}"
        )
        assert pins[0] == expected_pin, (
            f"{relative_path}: helper URL {pins[0]!r} does not match "
            f"{expected_pin!r}"
        )
    total += len(invocations)

assert total == 6, f"expected six active helper invocations, found {total}"
print("all six active workflow helper URLs match the configured package pin")
PY
}

@test "all six active IDD workflow helper URLs match the configured package pin" {
  run check_workflow_helper_pins
  assert_success
  assert_output "all six active workflow helper URLs match the configured package pin"
}
