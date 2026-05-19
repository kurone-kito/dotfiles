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
    $escapedHomeDir = $script:HomeDir.Replace('\', '\\')
    $body = @"
{
  "version": 1,
  "manager": "bitwarden",
  "os": "linux",
  "homeDir": "$escapedHomeDir",
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

Describe 'secret-status.ps1 DRIFT detection' -Skip:($IsWindows -eq $true) {
  BeforeAll {
    $script:StatePath = Join-Path $HomeDir '.config/chezmoi/secret-deploy-state.json'
    $script:OrigHome = $env:HOME
    $env:HOME = $HomeDir

    function script:Write-State {
      param([string]$Path, [string]$Sha)
      $body = @"
{
  "version": 1,
  "entries": [
    {"category":"secretFile","name":"s","path":"$Path","sha256":"$Sha","mode":"600","deployedAt":"2026-04-26T00:00:00Z"}
  ]
}
"@
      Set-Content -LiteralPath $script:StatePath -Value $body -NoNewline
    }

    function script:Get-Sha256 {
      param([string]$Path)
      (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  }

  AfterAll {
    if ($null -ne $script:OrigHome) { $env:HOME = $script:OrigHome }
    else { Remove-Item Env:HOME -ErrorAction SilentlyContinue }
  }

  AfterEach {
    Remove-Item -LiteralPath $StatePath -ErrorAction SilentlyContinue
    Remove-Item Env:SECRET_DEPLOY_STATE -ErrorAction SilentlyContinue
  }

  It 'secret file with sha mismatch is promoted to DRIFT' {
    $f = Join-Path $HomeDir 'secret.txt'
    Set-Content -LiteralPath $f -Value 'modified'
    & chmod 600 $f
    Write-State -Path $f -Sha ('0' * 64)
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'DRIFT'
    $r.Output | Should -Match 'content changed since deploy'
  }

  It 'secret file with matching sha stays OK' {
    $f = Join-Path $HomeDir 'secret-ok.txt'
    Set-Content -LiteralPath $f -Value 'expected'
    & chmod 600 $f
    Write-State -Path $f -Sha (Get-Sha256 -Path $f)
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret-ok.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 0
    $r.Output | Should -Not -Match 'DRIFT 1'
  }

  It 'row stays OK when no state record exists for the path' {
    $f = Join-Path $HomeDir 'secret-norec.txt'
    Set-Content -LiteralPath $f -Value 'anything'
    & chmod 600 $f
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret-norec.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 0
    $r.Output | Should -Not -Match 'DRIFT 1'
  }

  It 'WARN takes precedence over content drift' {
    $f = Join-Path $HomeDir 'secret-warn.txt'
    Set-Content -LiteralPath $f -Value 'changed'
    & chmod 644 $f
    Write-State -Path $f -Sha ('0' * 64)
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret-warn.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'WARN'
    $r.Output | Should -Not -Match 'DRIFT 1'
  }

  It 'ssh key DRIFT detected when only the public key drifts' {
    $priv = Join-Path $HomeDir '.ssh/id_test'
    $pub  = Join-Path $HomeDir '.ssh/id_test.pub'
    Set-Content -LiteralPath $priv -Value 'priv'
    & chmod 600 $priv
    Set-Content -LiteralPath $pub -Value 'pub-changed'
    & chmod 644 $pub
    $privSha = Get-Sha256 -Path $priv
    $body = @"
{
  "version": 1,
  "entries": [
    {"category":"sshKey","name":"k","path":"$priv","sha256":"$privSha","mode":"600","deployedAt":"2026-04-26T00:00:00Z"},
    {"category":"sshKey","name":"k.pub","path":"$pub","sha256":"deadbeef","mode":"644","deployedAt":"2026-04-26T00:00:00Z"}
  ]
}
"@
    Set-Content -LiteralPath $StatePath -Value $body -NoNewline
    $cats = @"
{"gpg":[],"sshKeys":[
  {"label":"k","item":"K","filename":"id_test","privatePath":"$priv","publicPath":"$pub"}
],"sshHosts":[],"secretFiles":[],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'DRIFT'
    $r.Output | Should -Match 'public key content changed'
  }

  It 'summary mode includes DRIFT counter' {
    $f = Join-Path $HomeDir 'secret-sum.txt'
    Set-Content -LiteralPath $f -Value 'modified'
    & chmod 600 $f
    Write-State -Path $f -Sha ('0' * 64)
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret-sum.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status -ExtraArgs @('-Summary')
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'DRIFT 1'
  }

  It 'JSON mode emits status=DRIFT' {
    $f = Join-Path $HomeDir 'secret-json.txt'
    Set-Content -LiteralPath $f -Value 'modified'
    & chmod 600 $f
    Write-State -Path $f -Sha ('0' * 64)
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret-json.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $r = Invoke-Status -ExtraArgs @('-Json')
    $r.ExitCode | Should -Be 1
    $obj = $r.Output | ConvertFrom-Json
    @($obj.rows | Where-Object status -eq 'DRIFT').Count | Should -BeGreaterThan 0
  }

  It 'SECRET_DEPLOY_STATE env override is honored' {
    $f = Join-Path $HomeDir 'secret-env.txt'
    Set-Content -LiteralPath $f -Value 'modified'
    & chmod 600 $f
    $alt = Join-Path $HomeDir 'alt-state.json'
    $body = @"
{"version":1,"entries":[{"category":"secretFile","name":"s","path":"$f","sha256":"deadbeef","mode":"600","deployedAt":"2026-04-26T00:00:00Z"}]}
"@
    Set-Content -LiteralPath $alt -Value $body -NoNewline
    $cats = @"
{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
  {"label":"s","item":"S","target":"secret-env.txt","absPath":"$f","attachment":""}
],"envFiles":[]}
"@
    Write-Manifest $cats
    $env:SECRET_DEPLOY_STATE = $alt
    $r = Invoke-Status
    $r.ExitCode | Should -Be 1
    $r.Output | Should -Match 'DRIFT'
  }
}
