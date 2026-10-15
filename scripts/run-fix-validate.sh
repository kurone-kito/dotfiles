#!/usr/bin/env bash
# The fix-validate pipeline: auto-fix and check Markdown, then spell-check the
# repository. It stops at the first command that fails and returns that
# command's exit status, like the `&&` chain it replaces. The IDD config runs
# it through scripts/with-pueue.sh so concurrent sessions queue up.
set -euo pipefail

npx markdownlint-cli2 --fix
npx markdownlint-cli2
npx cspell lint "**" --no-progress
