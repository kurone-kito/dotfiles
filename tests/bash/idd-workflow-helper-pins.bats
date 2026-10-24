#!/usr/bin/env bats
# Regression guards for issues #566 and #678: every live IDD workflow
# helper invocation uses the expected v0.17.0 archive pin, and the CI
# running timeout exceeds the verdict job's bounded review poll window.

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
expected_version = "0.17.0"
expected_package_spec = "https://codeload.github.com/kurone-kito/idd-skill/tar.gz/77befdd4030757464bed7f31c7dfe6d0a404a18b"
assert config["iddVersion"] == expected_version, (
    f"expected iddVersion {expected_version!r}, found {config['iddVersion']!r}"
)
expected_pin = config["helperRuntime"]["packageSpec"]
assert expected_pin == expected_package_spec, (
    f"expected v0.17.0 package pin, found {expected_pin!r}"
)

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

def workflow_job_timeouts(workflow):
    timeouts = {}
    in_jobs = False
    current_job = None
    for line in workflow.splitlines():
        if line == "jobs:":
            in_jobs = True
            continue
        if not in_jobs:
            continue
        if line and not line.startswith(" "):
            break
        job_match = re.fullmatch(r"  ([A-Za-z0-9_-]+):", line)
        if job_match:
            current_job = job_match.group(1)
            continue
        timeout_match = re.fullmatch(r"    timeout-minutes:\s*(\d+)", line)
        if current_job and timeout_match:
            timeouts[current_job] = int(timeout_match.group(1))
    return timeouts

def workflow_job_permissions(workflow, job_name):
    lines = workflow.splitlines()
    job_start = next(
        (index for index, line in enumerate(lines) if line == f"  {job_name}:"),
        None,
    )
    assert job_start is not None, f"workflow job {job_name!r} is missing"
    job_end = next(
        (
            index
            for index in range(job_start + 1, len(lines))
            if re.fullmatch(r"  [A-Za-z0-9_-]+:", lines[index])
        ),
        len(lines),
    )
    permissions_start = next(
        (
            index
            for index in range(job_start + 1, job_end)
            if lines[index] == "    permissions:"
        ),
        None,
    )
    assert permissions_start is not None, (
        f"workflow job {job_name!r} has no explicit permissions"
    )
    permissions = {}
    for line in lines[permissions_start + 1:job_end]:
        if not line.strip():
            continue
        indentation = len(line) - len(line.lstrip(" "))
        if indentation <= 4:
            break
        match = re.fullmatch(r"      ([A-Za-z0-9-]+):\s+(read|write)", line)
        assert match, f"unrecognized permission entry in {job_name!r}: {line!r}"
        permissions[match.group(1)] = match.group(2)
    return permissions

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
with open(os.path.join(root, ".github/workflows/idd-advisory-convergence.yml"), encoding="utf-8") as f:
    workflow = f.read()
expected_timeouts = {
    "idd-advisory-convergence": 14,
    "idd-advisory-convergence-self-waiver": 10,
}
actual_timeouts = workflow_job_timeouts(workflow)
assert actual_timeouts == expected_timeouts, (
    f"expected verdict/self-waiver timeouts {expected_timeouts!r}, "
    f"found {actual_timeouts!r}"
)
expected_ci_running_timeout = "PT16M"
actual_ci_running_timeout = config["ciWait"]["runningTimeout"]
assert actual_ci_running_timeout == expected_ci_running_timeout, (
    f"expected ciWait.runningTimeout {expected_ci_running_timeout!r}, "
    f"found {actual_ci_running_timeout!r}"
)
ci_wait_match = re.fullmatch(r"PT(\d+)M", actual_ci_running_timeout)
assert ci_wait_match is not None, (
    f"expected a whole-minute ciWait.runningTimeout, "
    f"found {actual_ci_running_timeout!r}"
)
ci_wait_minutes = int(ci_wait_match.group(1))
assert ci_wait_minutes > actual_timeouts["idd-advisory-convergence"], (
    f"ciWait.runningTimeout must exceed the verdict job timeout; "
    f"found {ci_wait_minutes} and "
    f"{actual_timeouts['idd-advisory-convergence']} minutes"
)
expected_verdict_permissions = {
    "contents": "read",
    "issues": "read",
    "pull-requests": "read",
    "actions": "read",
    "checks": "read",
}
actual_verdict_permissions = workflow_job_permissions(
    workflow, "idd-advisory-convergence"
)
assert actual_verdict_permissions == expected_verdict_permissions, (
    f"expected verdict permissions {expected_verdict_permissions!r}, "
    f"found {actual_verdict_permissions!r}"
)
expected_self_waiver_permissions = {
    "contents": "read",
    "pull-requests": "write",
    "issues": "write",
    "actions": "read",
    "checks": "read",
    "statuses": "read",
}
actual_self_waiver_permissions = workflow_job_permissions(
    workflow, "idd-advisory-convergence-self-waiver"
)
assert actual_self_waiver_permissions == expected_self_waiver_permissions, (
    f"expected self-waiver permissions {expected_self_waiver_permissions!r}, "
    f"found {actual_self_waiver_permissions!r}"
)
print(
    "all six active helper URLs, workflow timeouts, CI wait margin, and "
    "job permissions match the v0.17.0 contract"
)
PY
}

@test "active helper pins, workflow timeouts, CI wait margin, and job permissions match the v0.17.0 contract" {
  run check_workflow_helper_pins
  assert_success
  assert_output "all six active helper URLs, workflow timeouts, CI wait margin, and job permissions match the v0.17.0 contract"
}
