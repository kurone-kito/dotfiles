# Tests for the secret-status pwsh command.
#
# These tests exercise the same scenarios as tests/bash/secret-status.bats.
# They run cross-platform; on Windows the OS-specific verifiers are exercised
# in the secret-deploy-manifest.json.tmpl tests (rendering only). The runtime
# verification logic is platform-aware via $manifestOs from the manifest, so
# tests can simulate non-Windows verification by setting "os": "linux" in the
# manifest, which works on any host.

BeforeAll {
  $script:ScriptPath = Join-Path $PSScriptRoot '..' '..' 'home' 'dot_local' 'bin' 'executable_secret-status.ps1'
  $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("secret-status-" + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null
  $script:HomeDir = Join-Path $TmpRoot 'home'
  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir '.ssh') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $HomeDir '.config/chezmoi') | Out-Null
  if ($IsWindows -eq $false) { & chmod 700 (Join-Path $HomeDir '.ssh') }
  $script:Manifest = Join-Path $HomeDir '.config/chezmoi/secret-deploy-manifest.json'
  $env:NO_COLOR = '1'

  function script:Write-Manifest {
    param([string]$CategoriesJson)
    $body = @"
{
  "version": 1,
  "manager": "bitwarden",
  "os": "linux",
  "homeDir": "$script:HomeDir",
  "ghqRoot": "",
  "categories": $CategoriesJson
}
"@
    Set-Content -LiteralPath $script:Manifest -Value $body -NoNewline
  }

  function script:Invoke-Status {
    param([string[]]$ExtraArgs = @())
    $stdout = & pwsh -NoLogo -NoProfile -File $script:ScriptPath -Manifest $script:Manifest @ExtraArgs 2>&1
    return @{ Output = ($stdout -join "`n"); ExitCode = $LASTEXITCODE }
  }
}

AfterAll {
  if (Test-Path -LiteralPath $TmpRoot) {
    Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue
}

Describe 'secret-status.ps1' {
  It 'exits 2 when manifest file is missing' {
    Remove-Item -LiteralPath $Manifest -ErrorAction SilentlyContinue
    $r = Invoke-Status
    $r.ExitCode | Should -Be 2
    $r.Output | Should -Match 'manifest not found'
  }

  It 'exits 2 when manifest is invalid JSON' {
    Set-Content -LiteralPath $Manifest -Value 'not json' -NoNewline
    $r = Invoke-Status
    $r.ExitCode | Should -Be 2
    $r.Output | Should -Match 'not valid JSON'
  }

  It 'exits 0 when no deploy targets configured' {
    Write-Manifest '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
    $r = Invoke-Status
    $r.ExitCode | Should -Be 0
    $r.Output | Should -Match 'no deploy targets configured'
  }

  It 'summary mode prints one-line counts' {
    Write-Manifest '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
    $r = Invoke-Status -ExtraArgs @('-Summary')
    $r.ExitCode | Should -Be 0
    $r.Output | Should -Match 'secret-status:'
    $r.Output | Should -Match 'OK 0'
    $r.Output | Should -Match 'total 0'
  }

  It 'json mode emits parseable JSON' {
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"x","item":"X","target":"x.txt","absPath":"/nonexistent/x.txt","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status -ExtraArgs @('-Json')
    $obj = $r.Output | ConvertFrom-Json
    $obj.manager | Should -Be 'bitwarden'
    @($obj.rows | Where-Object status -eq 'MISSING').Count | Should -BeGreaterThan 0
  }

  It 'secret file present with correct mode is OK' -Skip:($IsWindows -eq $true) {
    $f = Join-Path $HomeDir 'secret.txt'
    Set-Content -LiteralPath $f -Value 'secret'
    & chmod 600 $f
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 0
    $r.Output | Should -Match 'OK'
  }

  It 'secret file with wrong mode is WARN' -Skip:($IsWindows -eq $true) {
    $f = Join-Path $HomeDir 'secret-bad.txt'
    Set-Content -LiteralPath $f -Value 'secret'
    & chmod 644 $f
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret-bad.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'WARN'
    $r.Output | Should -Match 'mode 644, want 600'
  }

  It 'secret file missing is MISSING' {
    $f = Join-Path $HomeDir 'never-existed.txt'
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"never-existed.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'MISSING'
  }

  It 'gpg without fingerprint is UNKNOWN' {
    Write-Manifest '{"gpg":[{"label":"x","item":"X","fingerprint":""}],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'UNKNOWN'
    $r.Output | Should -Match 'no expected fingerprint'
  }

  It 'env file UNKNOWN when ghq root unresolved' {
    $cats = '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[' +
      '{"label":"e","item":"E","repo":"github.com/me/x","filename":".env","subpath":"","absPath":"","attachment":""}' +
      ']}'
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'UNKNOWN'
    $r.Output | Should -Match 'ghq root unresolved'
  }

  It 'env file warns when filename not in .gitignore' -Skip:($IsWindows -eq $true) {
    $repo = Join-Path $HomeDir 'repo-warn'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo '.git') | Out-Null
    $envPath = Join-Path $repo '.env'
    Set-Content -LiteralPath $envPath -Value 'env'
    & chmod 600 $envPath
    Set-Content -LiteralPath (Join-Path $repo '.gitignore') -Value 'something-else'
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[
  {"label":"e","item":"E","repo":"github.com/me/x","filename":".env","subpath":"","absPath":"$envPath","attachment":""}
]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'WARN'
    $r.Output | Should -Match 'not in .gitignore'
  }

  It 'env file OK when gitignore lists filename' -Skip:($IsWindows -eq $true) {
    $repo = Join-Path $HomeDir 'repo-ok'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo '.git') | Out-Null
    $envPath = Join-Path $repo '.env'
    Set-Content -LiteralPath $envPath -Value 'env'
    & chmod 600 $envPath
    Set-Content -LiteralPath (Join-Path $repo '.gitignore') -Value '.env'
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[
  {"label":"e","item":"E","repo":"github.com/me/x","filename":".env","subpath":"","absPath":"$envPath","attachment":""}
]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 0
    $r.Output | Should -Match 'OK'
  }

  It '-NoColor suppresses ANSI even on TTY' {
    Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue
    Write-Manifest '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
    $r = Invoke-Status -ExtraArgs @('-NoColor')
    $env:NO_COLOR = '1'
    $r.ExitCode | Should -Be 0
    $r.Output | Should -Not -Match "`e\["
  }

  It 'NO_COLOR env disables ANSI' {
    Write-Manifest '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
    $r = Invoke-Status
    $r.ExitCode | Should -Be 0
    $r.Output | Should -Not -Match "`e\["
  }
}
