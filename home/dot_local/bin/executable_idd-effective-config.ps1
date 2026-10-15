#!/usr/bin/env pwsh
# Windows twin of executable_idd-effective-config (POSIX sh): exposes the
# upstream `idd-effective-config` helper of kurone-kito/idd-skill v0.16.0
# for the user-global IDD payload (dotfiles issue #646, roadmap #643). It
# runs commit e4d425ee28b1893dd45c4996b2506619018c4b2b from its codeload
# tarball through npx, which caches the package itself; nothing is
# installed globally, and repo-local IDD work keeps its v0.14.0 pin.
#
# Usage: idd-effective-config [--key <dotted.path>] [--no-user-global] [-h|--help]
& npx --yes --package 'https://codeload.github.com/kurone-kito/idd-skill/tar.gz/e4d425ee28b1893dd45c4996b2506619018c4b2b' idd-effective-config @args
exit $LASTEXITCODE
