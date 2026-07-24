# Tests for the secret-deploy-state pwsh helper.

BeforeAll {
  $script:ScriptPath = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home') 'dot_local') 'bin') 'executable_secret-deploy-state.ps1'

  # A real-world path can contain an apostrophe (e.g. a Windows
  # username like O'Connor), which would otherwise break the
  # generated -Command string before it ever reaches the script under
  # test. Every value interpolated into a single-quoted segment below
  # goes through this.
  function script:ConvertTo-PSSingleQuoted {
    param([string]$Value)
    "'" + ($Value -replace "'", "''") + "'"
  }

  # Run the helper in a fresh pwsh subprocess so we can isolate $env:HOME
  # and capture both stdout and stderr.
  function script:Invoke-Helper {
    param(
      [string]   $HomeDir,
      [string[]] $ScriptArgs = @(),
      [hashtable]$ExtraEnv = @{},
      # $IsWindows is ReadOnly+AllScope: Set-Variable -Force can stub it,
      # but the override leaks process-wide. Only ever apply it inside
      # this throwaway subprocess, never in the Pester process itself.
      [switch]   $SimulatePS51,
      # icacls does not exist on Linux/macOS CI. A PowerShell function
      # resolves before an external command of the same name, so
      # defining one here shims the call on every platform (including
      # real Windows, where it just shadows the real binary for this
      # one test) without needing a real icacls on PATH.
      [string]   $IcaclsMarkerPath
    )
    $stubBlock = ''
    if ($SimulatePS51) { $stubBlock += "Set-Variable -Name IsWindows -Value `$null -Force;" }
    if ($IcaclsMarkerPath) {
      $markerQ = ConvertTo-PSSingleQuoted $IcaclsMarkerPath
      $stubBlock += "function icacls { `$args -join ' ' | Out-File -FilePath $markerQ -Append };"
    }
    $envBlock = ''
    if ($HomeDir) { $envBlock += "`$env:HOME = $(ConvertTo-PSSingleQuoted $HomeDir);" }
    foreach ($k in $ExtraEnv.Keys) { $envBlock += "`$env:$k = $(ConvertTo-PSSingleQuoted $ExtraEnv[$k]);" }
    $argsExpr = ($ScriptArgs | ForEach-Object { ConvertTo-PSSingleQuoted $_ }) -join ' '
    $scriptPathQ = ConvertTo-PSSingleQuoted $script:ScriptPath
    $cmd = "$stubBlock$envBlock & $scriptPathQ $argsExpr 2>&1; exit `$LASTEXITCODE"
    $output = & pwsh -NoLogo -NoProfile -Command $cmd 2>&1
    return @{ Output = ($output -join "`n"); ExitCode = $LASTEXITCODE }
  }

  function script:New-FreshHome {
    $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sds-" + [Guid]::NewGuid().ToString('N'))
    $homeDir = Join-Path $tmpRoot 'home'
    New-Item -ItemType Directory -Force -Path (Join-Path $homeDir '.config/chezmoi') | Out-Null
    return $homeDir
  }

  function script:New-File {
    param([string]$Path, [string]$Content = 'hello')
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content)
    if ($IsWindows -eq $false) { & chmod 600 $Path }
  }

  function script:Get-Sha256 {
    param([string]$Content)
    $b = [Text.Encoding]::UTF8.GetBytes($Content)
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($b)) -replace '-', '').ToLower()
  }

  function script:Get-StateFor { param([string]$HomeDir) Join-Path $HomeDir '.config/chezmoi/secret-deploy-state.json' }
}

Describe 'secret-deploy-state.ps1' {

  It 'no args prints usage and exits 2' {
    $r = Invoke-Helper -HomeDir (New-FreshHome) -ScriptArgs @()
    $r.ExitCode | Should -Be 2
    $r.Output  | Should -Match 'Usage:'
  }

  It '--help exits 0' {
    $r = Invoke-Helper -HomeDir (New-FreshHome) -ScriptArgs @('--help')
    $r.ExitCode | Should -Be 0
    $r.Output  | Should -Match 'Usage:'
  }

  It 'path subcommand prints default state path' {
    $h = New-FreshHome
    $r = Invoke-Helper -HomeDir $h -ScriptArgs @('path')
    $r.ExitCode    | Should -Be 0
    $r.Output.Trim() | Should -Be (Get-StateFor -HomeDir $h)
  }

  It 'SECRET_DEPLOY_STATE override is honored' {
    $h = New-FreshHome
    $alt = Join-Path ([System.IO.Path]::GetTempPath()) ("alt-" + [Guid]::NewGuid().ToString('N') + ".json")
    $r = Invoke-Helper -HomeDir $h -ScriptArgs @('path') -ExtraEnv @{ SECRET_DEPLOY_STATE = $alt }
    $r.ExitCode    | Should -Be 0
    $r.Output.Trim() | Should -Be $alt
  }

  It 'record creates state file with sha256 matching content' {
    $h = New-FreshHome
    $f = Join-Path $h '.secret/x.txt'
    New-File -Path $f -Content 'abc'
    $r = Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'secretFile', 'x', $f)
    $r.ExitCode | Should -Be 0
    $state = Get-StateFor -HomeDir $h
    Test-Path $state | Should -BeTrue
    $j = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
    $entry = $j.entries | Where-Object { $_.path -eq $f } | Select-Object -First 1
    $entry             | Should -Not -BeNullOrEmpty
    $entry.sha256      | Should -Be (Get-Sha256 -Content 'abc')
    $entry.category    | Should -Be 'secretFile'
    $entry.name        | Should -Be 'x'
    # ConvertFrom-Json may parse the ISO string back to DateTime; just check it's truthy
    $entry.deployedAt | Should -Not -BeNullOrEmpty
  }

  It 'record upserts existing entry by path (no duplicates)' {
    $h = New-FreshHome
    $f = Join-Path $h '.secret/y.txt'
    New-File -Path $f -Content 'v1'
    Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'secretFile', 'y', $f) | Out-Null
    [System.IO.File]::WriteAllText($f, 'v2')
    Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'secretFile', 'y', $f) | Out-Null
    $j = Get-Content -LiteralPath (Get-StateFor -HomeDir $h) -Raw | ConvertFrom-Json
    @($j.entries | Where-Object { $_.path -eq $f }).Count | Should -Be 1
    ($j.entries | Where-Object { $_.path -eq $f })[0].sha256 | Should -Be (Get-Sha256 -Content 'v2')
  }

  It 'record preserves entries for other paths' {
    $h = New-FreshHome
    $a = Join-Path $h '.secret/a.txt'; New-File -Path $a -Content 'A'
    $b = Join-Path $h '.secret/b.txt'; New-File -Path $b -Content 'B'
    Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'secretFile', 'a', $a) | Out-Null
    Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'secretFile', 'b', $b) | Out-Null
    $j = Get-Content -LiteralPath (Get-StateFor -HomeDir $h) -Raw | ConvertFrom-Json
    @($j.entries).Count | Should -Be 2
  }

  It 'record on missing file is best-effort (exit 0, state untouched)' {
    $h = New-FreshHome
    $r = Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'secretFile', 'gone', (Join-Path $h '.secret/nope.txt'))
    $r.ExitCode | Should -Be 0
    $r.Output   | Should -Match 'file not found'
    Test-Path (Get-StateFor -HomeDir $h) | Should -BeFalse
  }

  It 'record with relative path is best-effort skip' {
    $h = New-FreshHome
    $r = Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'secretFile', 'rel', 'relative/path')
    $r.ExitCode | Should -Be 0
    $r.Output   | Should -Match 'must be absolute'
  }

  It 'record with too few args exits 2' {
    $h = New-FreshHome
    $r = Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'only-one')
    $r.ExitCode | Should -Be 2
  }

  It 'unknown subcommand exits 2' {
    $h = New-FreshHome
    $r = Invoke-Helper -HomeDir $h -ScriptArgs @('gibberish')
    $r.ExitCode | Should -Be 2
  }
}

Describe 'secret-deploy-state.ps1 (PS5.1 $IsWindows guard)' {

  It 'takes the icacls branch and leaves mode empty when $IsWindows is $null (PS5.1 emulation)' {
    $h = New-FreshHome
    $f = Join-Path $h '.secret/ps51.txt'
    New-File -Path $f -Content 'abc'
    $marker = Join-Path ([System.IO.Path]::GetTempPath()) ("icacls-marker-" + [Guid]::NewGuid().ToString('N') + '.txt')

    try {
      $r = Invoke-Helper -HomeDir $h -ScriptArgs @('record', 'secretFile', 'ps51', $f) `
        -ExtraEnv @{ USERNAME = 'testuser' } -SimulatePS51 -IcaclsMarkerPath $marker

      $r.ExitCode | Should -Be 0
      # Proves the icacls branch ran instead of the pre-fix silent no-op.
      Test-Path -LiteralPath $marker | Should -BeTrue

      $j = Get-Content -LiteralPath (Get-StateFor -HomeDir $h) -Raw | ConvertFrom-Json
      $entry = $j.entries | Where-Object { $_.path -eq $f } | Select-Object -First 1
      $entry             | Should -Not -BeNullOrEmpty
      # Proves Get-FileMode returned '' instead of shelling out to stat.
      $entry.mode        | Should -BeNullOrEmpty
    } finally {
      Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    }
  }
}
