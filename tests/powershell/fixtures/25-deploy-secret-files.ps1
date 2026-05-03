# Pre-rendered test fixture for run_onchange_after_25-deploy-secret-files.ps1.tmpl.
# Contains two hardcoded entries:
#   aws-credentials - deploys to .aws/credentials
#   docker-auth     - deploys to .docker/config.json
#
# This script is intentionally NOT a chezmoi template.
# It simulates what chezmoi would render when the following config
# is present in chezmoi.toml:
#
#   [data.secret]
#   manager = "bitwarden"
#
#   [data.secret.files.aws-credentials]
#   item = "AWS Credentials"
#   target = ".aws/credentials"
#   attachment = "credentials"
#
#   [data.secret.files.docker-auth]
#   item = "Docker Registry Auth"
#   target = ".docker/config.json"
#   attachment = "config.json"
#
# Set DOTFILES_TEST_HOME to redirect deployment to a test directory.

$deployHome = if ($env:DOTFILES_TEST_HOME) { $env:DOTFILES_TEST_HOME } else { $HOME }

Write-Host "==> aws-credentials: ~/.aws/credentials"

$targetPath = Join-Path $deployHome '.aws/credentials'
$targetDir = Split-Path -Parent $targetPath

if (-not (Test-Path $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  & icacls $targetDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to restrict permissions on ${targetDir} (icacls exit code: $LASTEXITCODE)"
  }
}

@'
[default]
aws_access_key_id = AKIAEXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
'@ | Set-Content -Path $targetPath -NoNewline -Encoding UTF8

& icacls $targetPath /inheritance:r /grant:r "${env:USERNAME}:(R,W)" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Warning "Failed to restrict permissions on ${targetPath} (icacls exit code: $LASTEXITCODE)"
}
Write-Host "  done: deployed (user-only access)"

Write-Host "==> docker-auth: ~/.docker/config.json"

$targetPath = Join-Path $deployHome '.docker/config.json'
$targetDir = Split-Path -Parent $targetPath

if (-not (Test-Path $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  & icacls $targetDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to restrict permissions on ${targetDir} (icacls exit code: $LASTEXITCODE)"
  }
}

@'
{"auths":{"registry.example.com":{"auth":"dXNlcjpwYXNz"}}}
'@ | Set-Content -Path $targetPath -NoNewline -Encoding UTF8

& icacls $targetPath /inheritance:r /grant:r "${env:USERNAME}:(R,W)" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Warning "Failed to restrict permissions on ${targetPath} (icacls exit code: $LASTEXITCODE)"
}
Write-Host "  done: deployed (user-only access)"

Write-Host "secret file deploy complete."
