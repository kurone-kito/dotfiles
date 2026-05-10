#!/usr/bin/env pwsh
# Pre-rendered test fixture for generate-git-profiles.ps1.tmpl.
# Contains two hardcoded profiles:
#   personal  - name and email only (no GPG)
#   work      - name, email, and GPG signingkey
#
# This script is intentionally NOT a chezmoi template.
# It simulates what chezmoi would render when the following config
# is present in chezmoi.toml:
#
#   [data.git.profiles.personal]
#     name  = "Personal User"
#     email = "personal@example.com"
#   [data.git.profiles.work]
#     name       = "Work User"
#     email      = "work@example.com"
#     signingkey = "ABCD1234ABCD1234"
$ErrorActionPreference = 'Stop'

$profilesDir = if ($env:PROFILES_DIR) {
  $env:PROFILES_DIR
}
else {
  Join-Path $HOME '.config/git/profiles'
}
New-Item -ItemType Directory -Path $profilesDir -Force | Out-Null

$profilePath = Join-Path $profilesDir 'personal'
@'
[user]
  email = "personal@example.com"
  name = "Personal User"
'@ | Set-Content -Path $profilePath -Encoding utf8NoBOM

$profilePath = Join-Path $profilesDir 'work'
@'
[user]
  email = "work@example.com"
  name = "Work User"
  signingkey = "ABCD1234ABCD1234"
[commit]
  gpgsign = true
[tag]
  forceSignAnnotated = true
  gpgsign = true
'@ | Set-Content -Path $profilePath -Encoding utf8NoBOM

$validProfiles = @(
  'personal'
  'work'
)

Get-ChildItem -Path $profilesDir -File |
  Where-Object { $validProfiles -notcontains $_.Name } |
  Remove-Item -Force
