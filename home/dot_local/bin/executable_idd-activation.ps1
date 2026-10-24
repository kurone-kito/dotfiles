#!/usr/bin/env pwsh
# Windows twin of executable_idd-activation (POSIX sh): exposes the
# upstream `idd-activation` helper of kurone-kito/idd-skill v0.17.0 for the
# user-global IDD payload (dotfiles issue #676; originally introduced by #646
# under roadmap #643). It runs commit
# 77befdd4030757464bed7f31c7dfe6d0a404a18b from its codeload
# tarball through npx, which caches the package itself; nothing is
# installed globally, and repo-local IDD work keeps its v0.14.0 pin.
#
# The upstream CLI exits 0 with no output on a Node.js below its engines
# floor, and a bare `& npx` leaves $LASTEXITCODE unset when npx is missing,
# which would report success. So check for npx and that floor first, and
# exit 1 with a message instead.
#
# Usage: idd-activation [--cwd <path>] [-h|--help]
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine('idd-activation: npx is required (Node.js 22.23.2+, 24.2.0+, or 26+)')
  exit 1
}
& node -e "const [a, b, c] = process.versions.node.split('.').map(Number); process.exit((a === 22 && (b > 23 || (b === 23 && c >= 2))) || (a === 24 && b >= 2) || a >= 26 ? 0 : 1);" 2>$null
if ($LASTEXITCODE -ne 0) {
  [Console]::Error.WriteLine('idd-activation: needs Node.js 22.23.2+, 24.2.0+, or 26+')
  exit 1
}
& npx --yes --package 'https://codeload.github.com/kurone-kito/idd-skill/tar.gz/77befdd4030757464bed7f31c7dfe6d0a404a18b' idd-activation @args
exit $LASTEXITCODE
