# Tests for the opt-in mkcert local CA setup chezmoi run_onchange
# script (home/run_onchange_after_57-setup-mkcert-ca.ps1.tmpl).
#
# Unlike most run_onchange suites in this directory, this one renders
# the real template via `chezmoi execute-template` (mirrors
# winget-user-path-packages-tmpl.Tests.ps1 / signing-resolve.Tests.ps1)
# instead of using a single static pre-rendered fixture: this script's
# core branch (not just the `.chezmoi.os` guard) is baked in at
# chezmoi-render time from `data.mkcert.install`, so a single static
# fixture could only ever represent one of the two opt-in states. A
# rendered-content diff between the two states is also the mechanical
# proxy for "toggling the opt-in re-triggers run_onchange": chezmoi
# keys run_onchange_* re-execution off the rendered script's content
# hash, so a changed rendering is sufficient evidence.
#
# Runtime (Get-Command/mkcert) mocking runs inside a fully separate
# child `pwsh -NoProfile` process (mirrors 55-setup-editors.Tests.ps1)
# rather than shadowing Get-Command directly in this Pester session,
# since Get-Command is used pervasively by Pester itself and by every
# other suite file sharing the same `Invoke-Pester tests/powershell/`
# run. The script itself invokes mkcert inside a background job (see
# its own comments on why -- a bounded wait against a call that has
# been observed to hang), and PowerShell jobs run in a fresh runspace
# that does not inherit function definitions from the calling scope,
# so the `mkcert` mock is injected via the script's
# DOTFILES_TEST_MKCERT_JOB_INIT test seam (a path to a file the job
# loads as its -InitializationScript) rather than as an ordinary
# function definition in the wrapping child process.
#
# Skipped entirely when chezmoi is not available on PATH (CI installs
# it explicitly; see .github/workflows/test.yml).

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoHome = Join-Path (Join-Path $PSScriptRoot '..') '..' | Join-Path -ChildPath 'home' | Resolve-Path
  $script:TemplatePath = Join-Path $script:RepoHome 'run_onchange_after_57-setup-mkcert-ca.ps1.tmpl'
  $script:RepoRoot = (Join-Path $script:RepoHome '..' | Resolve-Path).Path
  $script:ConfigTemplatePath = Join-Path $script:RepoRoot '.chezmoi.toml.tmpl'

  # Renders .chezmoi.toml.tmpl the way `chezmoi init` does, with the git and
  # secret prompts answered on the command line. $MkcertJson is the value of
  # data.mkcert as a JSON object, or $null to leave the table out entirely.
  # Windows PowerShell 5.1 turns stderr into ErrorRecords under Stop, so the
  # capture runs in a child scriptblock with 'Continue' (as in Invoke-Render).
  function Invoke-ConfigRender {
    param([AllowNull()] [string] $MkcertJson)
    $data = if ([string]::IsNullOrEmpty($MkcertJson)) { '{}' } else { '{ "mkcert": ' + $MkcertJson + ' }' }
    $cfg = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-initcfg-{0}.json" -f [guid]::NewGuid())
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-initdest-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    [System.IO.File]::WriteAllText($cfg, '{ "data": ' + $data + ' }', [System.Text.UTF8Encoding]::new($false))
    try {
      $raw = & {
        $ErrorActionPreference = 'Continue'
        & chezmoi execute-template --init --file $script:ConfigTemplatePath --config $cfg --config-format json `
          --promptString git.name='Test User' --promptString git.email='test@example.com' `
          --promptString git.signingkey='' --promptString secret.manager='none' `
          --source $script:RepoRoot --destination $dest 2>&1
      }
      $exitCode = $LASTEXITCODE
      $lines = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
      [pscustomobject]@{
        ExitCode = $exitCode
        Output   = ($lines -join "`n")
      }
    } finally {
      Remove-Item -LiteralPath $cfg, $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  # Renders the run_onchange script from a config file that already holds
  # TOML text, so a generated config can be fed back in as chezmoi would
  # read it on the next apply. The OS is pinned to windows.
  function Invoke-RenderOnChangeFromToml {
    param([string] $ConfigToml)
    $cfg = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-roundtrip-{0}.toml" -f [guid]::NewGuid())
    $osFile = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-roundtrip-os-{0}.json" -f [guid]::NewGuid())
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-roundtrip-dest-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    [System.IO.File]::WriteAllText($cfg, $ConfigToml, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($osFile, '{"chezmoi":{"os":"windows"}}', [System.Text.UTF8Encoding]::new($false))
    try {
      $raw = & {
        $ErrorActionPreference = 'Continue'
        & chezmoi execute-template --file $script:TemplatePath --config $cfg --config-format toml `
          --override-data-file $osFile --source $script:RepoHome --destination $dest 2>&1
      }
      $exitCode = $LASTEXITCODE
      # Keep ErrorRecords too: chezmoi reports a failed render on stderr.
      $lines = @($raw | ForEach-Object { $_.ToString() })
      [pscustomobject]@{
        ExitCode = $exitCode
        Output   = ($lines -join "`n")
      }
    } finally {
      Remove-Item -LiteralPath $cfg, $osFile, $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  function Invoke-Render {
    param(
      [bool] $Install,
      [string] $Os = 'windows',
      # Optional data.mkcert.installTimeoutSeconds; $null leaves the key unset.
      [object] $InstallTimeoutSeconds = $null
    )
    $mkcertCfg = @{ install = $Install }
    if ($null -ne $InstallTimeoutSeconds) {
      $mkcertCfg['installTimeoutSeconds'] = $InstallTimeoutSeconds
    }
    $cfgObj = @{ data = @{ mkcert = $mkcertCfg } }
    $cfg = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-cfg-{0}.json" -f [guid]::NewGuid())
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-dest-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $json = $cfgObj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($cfg, $json, [System.Text.UTF8Encoding]::new($false))
    # --override-data-file rather than the inline --override-data
    # string: Windows PowerShell 5.1's native-command argument passing
    # mangles embedded double-quotes in a `{"chezmoi":{"os":"..."}}`
    # style argument (stripping them and producing invalid JSON),
    # unlike PowerShell 7+ -- passing a bare file path instead avoids
    # that native-argv-quoting difference entirely.
    $overrideDataFile = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-override-{0}.json" -f [guid]::NewGuid())
    $overrideJson = "{`"chezmoi`":{`"os`":`"$Os`"}}"
    [System.IO.File]::WriteAllText($overrideDataFile, $overrideJson, [System.Text.UTF8Encoding]::new($false))
    try {
      # Windows PowerShell 5.1 turns a native command's stderr (the render
      # failure text) into a terminating RemoteException under Pester's
      # ErrorActionPreference = 'Stop'. Continue here, local to this
      # function, so a failed render returns ExitCode and Output instead.
      $ErrorActionPreference = 'Continue'
      $output = & chezmoi execute-template --file $script:TemplatePath `
        --config $cfg --config-format json `
        --override-data-file $overrideDataFile `
        --source $script:RepoHome --destination $dest 2>&1
      [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output -join "`n")
      }
    } finally {
      Remove-Item -Path $cfg, $dest, $overrideDataFile -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  function Invoke-RenderedScript {
    param(
      [string] $ScriptContent,
      [string] $GetCommandMock,
      [string] $MkcertJobInit,
      [int] $TimeoutSeconds
    )
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-run-{0}.ps1" -f [guid]::NewGuid())
    [System.IO.File]::WriteAllText($tmp, $ScriptContent, [System.Text.UTF8Encoding]::new($false))

    $jobInitFile = $null
    if ($MkcertJobInit) {
      $jobInitFile = Join-Path ([IO.Path]::GetTempPath()) ("mkcert-ca-jobinit-{0}.ps1" -f [guid]::NewGuid())
      [System.IO.File]::WriteAllText($jobInitFile, $MkcertJobInit, [System.Text.UTF8Encoding]::new($false))
    }

    try {
      $escapedPath = $tmp -replace "'", "''"
      $envSetup = ''
      if ($jobInitFile) {
        $escapedInit = $jobInitFile -replace "'", "''"
        $envSetup += "`$env:DOTFILES_TEST_MKCERT_JOB_INIT = '$escapedInit'`n"
      }
      if ($TimeoutSeconds) {
        $envSetup += "`$env:DOTFILES_TEST_MKCERT_INSTALL_TIMEOUT_SECONDS = '$TimeoutSeconds'`n"
      }
      $command = "$envSetup$GetCommandMock`n& '$escapedPath'`nexit `$LASTEXITCODE"
      $output = & pwsh -NoProfile -Command $command 2>&1
      [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String)
      }
    } finally {
      Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
      if ($jobInitFile) { Remove-Item -Path $jobInitFile -Force -ErrorAction SilentlyContinue }
    }
  }
}

Describe '57-setup-mkcert-ca' -Skip:(-not $script:HasChezmoi) {

  Context 'chezmoi template rendering' {
    It 'renders nothing on non-Windows regardless of the opt-in value' {
      (Invoke-Render -Install $false -Os 'linux').Output.Trim() | Should -BeNullOrEmpty
      (Invoke-Render -Install $true -Os 'linux').Output.Trim() | Should -BeNullOrEmpty
    }

    It 'renders successfully on Windows for both opt-in values' {
      (Invoke-Render -Install $false -Os 'windows').ExitCode | Should -Be 0
      (Invoke-Render -Install $true -Os 'windows').ExitCode | Should -Be 0
    }

    It 'toggling the opt-in changes the rendered content (forces run_onchange re-execution)' {
      $disabled = (Invoke-Render -Install $false -Os 'windows').Output
      $enabled = (Invoke-Render -Install $true -Os 'windows').Output
      $disabled | Should -Not -Be $enabled
      $disabled | Should -Match 'mkcert install opt-in: false'
      $enabled | Should -Match 'mkcert install opt-in: true'
    }

    It 'renders the 180-second bounded wait when installTimeoutSeconds is unset' {
      $rendered = (Invoke-Render -Install $true -Os 'windows').Output
      $rendered | Should -Match '(?s)\}\s*else\s*\{\s*180\s*\}'
    }

    It 'renders a configured installTimeoutSeconds into the bounded wait' {
      $rendered = (Invoke-Render -Install $true -Os 'windows' -InstallTimeoutSeconds 45).Output
      $rendered | Should -Match '(?s)\}\s*else\s*\{\s*45\s*\}'
      $rendered | Should -Not -Match '(?s)\}\s*else\s*\{\s*180\s*\}'
    }

    It 'renders the largest accepted value, 2147483647, which is the Int32 limit of Wait-Job -Timeout' {
      $rendered = (Invoke-Render -Install $true -Os 'windows' -InstallTimeoutSeconds 2147483647).Output
      $rendered | Should -Match '(?s)\}\s*else\s*\{\s*2147483647\s*\}'
    }

    It 'fails the render and names installTimeoutSeconds for a value that is not a positive integer up to 2147483647: <_>' -ForEach @(0, -1, 1.5, 'abc', '180', $true, 2147483648) {
      $result = Invoke-Render -Install $true -Os 'windows' -InstallTimeoutSeconds $_
      $result.ExitCode | Should -Not -Be 0
      $result.Output | Should -Match 'installTimeoutSeconds'
    }
  }

  Context 'chezmoi init config emission (.chezmoi.toml.tmpl)' {
    It 'emits no [data.mkcert] table when both keys are unset' {
      $result = Invoke-ConfigRender -MkcertJson $null
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Not -Match '(?m)^\[data\.mkcert\]'
    }

    It 'emits no table when installTimeoutSeconds is the integer default 180' {
      $result = Invoke-ConfigRender -MkcertJson '{ "installTimeoutSeconds": 180 }'
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Not -Match '(?m)^\[data\.mkcert\]'
    }

    It 'emits install = true without an installTimeoutSeconds line when only install is set' {
      $result = Invoke-ConfigRender -MkcertJson '{ "install": true }'
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match '(?m)^\[data\.mkcert\]\ninstall = true$'
      $result.Output | Should -Not -Match 'installTimeoutSeconds'
    }

    It 'emits a configured integer as a bare number that the script render accepts' {
      $result = Invoke-ConfigRender -MkcertJson '{ "install": true, "installTimeoutSeconds": 45 }'
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match '(?m)^installTimeoutSeconds = 45$'
      $roundTrip = Invoke-RenderOnChangeFromToml -ConfigToml $result.Output
      $roundTrip.ExitCode | Should -Be 0
      $roundTrip.Output | Should -Match '(?s)\}\s*else\s*\{\s*45\s*\}'
    }

    It 'emits a quoted invalid value and the script render rejects it, naming the key' {
      $result = Invoke-ConfigRender -MkcertJson '{ "install": true, "installTimeoutSeconds": "180" }'
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match '(?m)^installTimeoutSeconds = "180"$'
      $roundTrip = Invoke-RenderOnChangeFromToml -ConfigToml $result.Output
      $roundTrip.ExitCode | Should -Not -Be 0
      $roundTrip.Output | Should -Match 'installTimeoutSeconds'
    }
  }

  Context 'runtime behavior when the opt-in is disabled' {
    It 'prints a skip message, exits 0, and never touches mkcert' {
      $rendered = (Invoke-Render -Install $false -Os 'windows').Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  throw "Get-Command should not be called for '$Name' when the opt-in is disabled"
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match 'not opted in'
    }
  }

  Context 'runtime behavior when the opt-in is enabled' {
    It 'warns and exits non-zero when mkcert is not on PATH' {
      $rendered = (Invoke-Render -Install $true -Os 'windows').Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  $null
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock
      $result.ExitCode | Should -Not -Be 0
      $result.Output | Should -Match 'not on PATH'
    }

    It 'invokes mkcert -install exactly once when mkcert is present, and reports success' {
      $rendered = (Invoke-Render -Install $true -Os 'windows').Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  if ($Name -eq 'mkcert') {
    [pscustomobject]@{ Name = 'mkcert'; Path = 'mkcert'; Source = 'mkcert' }
  } else { $null }
}
'@
      $mkcertJobInit = @'
function mkcert {
  Write-Host ('mkcert-invoked-with:' + ($args -join ' '))
  $global:LASTEXITCODE = 0
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock -MkcertJobInit $mkcertJobInit
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match 'mkcert-invoked-with:-install'
      $result.Output | Should -Match 'installed/verified'
    }

    It 'surfaces mkcert''s own console output rather than discarding it' {
      # Regression coverage: the job scriptblock merges native
      # stdout/stderr via `2>&1`, so a real mkcert.exe's own text
      # (e.g. "Created a new local CA") reaches Receive-Job as plain
      # pipeline output distinct from Write-Host's Information stream
      # -- assert on that distinct channel specifically so this test
      # cannot pass merely because Write-Host output (used by the
      # other mocks here) already flows through unaffected.
      $rendered = (Invoke-Render -Install $true -Os 'windows').Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  if ($Name -eq 'mkcert') {
    [pscustomobject]@{ Name = 'mkcert'; Path = 'mkcert'; Source = 'mkcert' }
  } else { $null }
}
'@
      $mkcertJobInit = @'
function mkcert {
  'Created a new local CA (mock pipeline output)'
  $global:LASTEXITCODE = 0
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock -MkcertJobInit $mkcertJobInit
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match 'Created a new local CA \(mock pipeline output\)'
    }

    It 'propagates a non-zero mkcert -install exit code as a warning and matching non-zero exit' {
      $rendered = (Invoke-Render -Install $true -Os 'windows').Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  if ($Name -eq 'mkcert') {
    [pscustomobject]@{ Name = 'mkcert'; Path = 'mkcert'; Source = 'mkcert' }
  } else { $null }
}
'@
      $mkcertJobInit = @'
function mkcert {
  $global:LASTEXITCODE = 7
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock -MkcertJobInit $mkcertJobInit
      $result.ExitCode | Should -Be 7
      $result.Output | Should -Match 'exited with code 7'
    }

    It 'warns and exits non-zero when mkcert -install does not complete within the bounded timeout' {
      # Regression coverage for the empirically observed hang (see
      # docs/mkcert-local-ca.md): mkcert -install can block
      # indefinitely on an unanswered trust-store confirmation dialog
      # in a non-interactive session. The script must not hang forever
      # -- it bounds the wait and fails loudly instead. A short
      # DOTFILES_TEST_MKCERT_INSTALL_TIMEOUT_SECONDS keeps this test
      # fast rather than waiting out the real 180s production default.
      # 5s (not shorter) is deliberate: empirically, a background
      # job's very first pipeline output can take a moment to
      # transport back to the parent job object, and a 1-2s window
      # flakes waiting on it even though the output was genuinely
      # produced -- 5s reliably clears that startup latency without
      # meaningfully slowing the suite.
      $rendered = (Invoke-Render -Install $true -Os 'windows').Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  if ($Name -eq 'mkcert') {
    [pscustomobject]@{ Name = 'mkcert'; Path = 'mkcert'; Source = 'mkcert' }
  } else { $null }
}
'@
      # Prints output before hanging, mirroring this PR's own CI probe
      # finding: real mkcert.exe prints "Created a new local CA" and
      # then hangs while registering it into the trust store. The
      # script should salvage and surface that partial output.
      $mkcertJobInit = @'
function mkcert {
  'Created a new local CA (mock partial output)'
  Start-Sleep -Seconds 20
  $global:LASTEXITCODE = 0
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock `
        -MkcertJobInit $mkcertJobInit -TimeoutSeconds 5
      $result.ExitCode | Should -Not -Be 0
      $result.Output | Should -Match 'Created a new local CA \(mock partial output\)'
      $result.Output | Should -Match 'did not complete within 5s'
    }

    It 'lets the test-only environment variable override a configured installTimeoutSeconds' {
      # Precedence: the test variable, then data.mkcert.installTimeoutSeconds,
      # then the 180s default. The configured 45s would let the 20s mock
      # finish successfully, so only the 5s test variable can produce the
      # timeout failure asserted below.
      $rendered = (Invoke-Render -Install $true -Os 'windows' -InstallTimeoutSeconds 45).Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  if ($Name -eq 'mkcert') {
    [pscustomobject]@{ Name = 'mkcert'; Path = 'mkcert'; Source = 'mkcert' }
  } else { $null }
}
'@
      $mkcertJobInit = @'
function mkcert {
  Start-Sleep -Seconds 20
  $global:LASTEXITCODE = 0
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock `
        -MkcertJobInit $mkcertJobInit -TimeoutSeconds 5
      $result.ExitCode | Should -Not -Be 0
      $result.Output | Should -Match 'did not complete within 5s'
    }

    It 'falls back to Source when Get-Command reports no Path' {
      $rendered = (Invoke-Render -Install $true -Os 'windows').Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  if ($Name -eq 'mkcert') {
    [pscustomobject]@{ Name = 'mkcert'; Path = $null; Source = 'mkcert' }
  } else { $null }
}
'@
      $mkcertJobInit = @'
function mkcert {
  Write-Host 'source-fallback-used'
  $global:LASTEXITCODE = 0
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock -MkcertJobInit $mkcertJobInit
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match 'source-fallback-used'
    }

    It 'prefers Path over Source when Get-Command reports both' {
      $rendered = (Invoke-Render -Install $true -Os 'windows').Output
      $getCommandMock = @'
function Get-Command {
  param([string]$Name, [string]$CommandType, [string]$ErrorAction)
  if ($Name -eq 'mkcert') {
    [pscustomobject]@{ Name = 'mkcert'; Path = 'mkcert-via-path'; Source = 'mkcert-via-source' }
  } else { $null }
}
'@
      $mkcertJobInit = @'
function mkcert-via-path {
  Write-Host 'path-preferred'
  $global:LASTEXITCODE = 0
}
function mkcert-via-source {
  throw 'Source should not be invoked when Path is populated'
}
'@
      $result = Invoke-RenderedScript -ScriptContent $rendered -GetCommandMock $getCommandMock -MkcertJobInit $mkcertJobInit
      $result.ExitCode | Should -Be 0
      $result.Output | Should -Match 'path-preferred'
      $result.Output | Should -Not -Match 'Source should not be invoked'
    }
  }
}
