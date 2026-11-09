# Tests for the run_onchange_after_link-powershell-profile chezmoi script.
# The once-per-startup loader texts run in child processes on every
# platform. The linker body is Windows-only (the template renders it only
# on Windows), and it runs only against temporary profile roots, never the
# user's Documents folders.

BeforeAll {
  $script:Template = Join-Path $PSScriptRoot `
    '../../home/run_onchange_after_link-powershell-profile.ps1.tmpl'
  $script:Raw = Get-Content -LiteralPath $script:Template -Raw
  $script:Pwsh = (Get-Process -Id $PID).Path

  function script:Get-HereText([string]$Name) {
    $pattern = '(?s)\$' + $Name + " = @'\r?\n(.*?)\r?\n'@"
    $match = [regex]::Match($script:Raw, $pattern)
    if (-not $match.Success) { throw "here-string not found: $Name" }
    return $match.Groups[1].Value
  }

  function script:Invoke-Child {
    param([string]$ScriptPath, [string]$HomeDir)
    $savedHome = $env:HOME
    $savedUserProfile = $env:USERPROFILE
    try {
      $env:HOME = $HomeDir
      $env:USERPROFILE = $HomeDir
      & $script:Pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath | Out-Null
    } finally {
      $env:HOME = $savedHome
      $env:USERPROFILE = $savedUserProfile
    }
  }

  function script:New-ConfigHome {
    $homeDir = Join-Path $TestDrive ('home-' + [guid]::NewGuid().ToString('N'))
    $configDir = Join-Path $homeDir (Join-Path '.config' 'powershell')
    $null = New-Item -ItemType Directory -Path $configDir -Force
    # The config profile counts each run and throws once when a flag file
    # named throw-once exists in the home directory.
    $config = @'
Add-Content -LiteralPath (Join-Path $HOME 'count.log') -Value 'run'
$flag = Join-Path $HOME 'throw-once'
if (Test-Path -LiteralPath $flag) {
  Remove-Item -LiteralPath $flag
  throw 'config boom'
}
'@
    Set-Content -LiteralPath (Join-Path $configDir 'profile.ps1') -Value $config
    return $homeDir
  }

  function script:New-ChildScript([string[]]$Lines) {
    $path = Join-Path $TestDrive ('child-' + [guid]::NewGuid().ToString('N') + '.ps1')
    Set-Content -LiteralPath $path -Value ($Lines -join "`n")
    return $path
  }

  $script:AllHostsPath = Join-Path $TestDrive 'all-hosts.ps1'
  $script:HostPath = Join-Path $TestDrive 'host.ps1'
  Set-Content -LiteralPath $script:AllHostsPath `
    -Value (Get-HereText 'loaderAllHosts') -Encoding utf8
  Set-Content -LiteralPath $script:HostPath `
    -Value (Get-HereText 'loaderHost') -Encoding utf8

  # Child prelude: strict errors, a run counter, and the once-per-startup signal.
  $script:Prelude = @(
    '$ErrorActionPreference = "Stop"'
    'function Get-Count { $p = Join-Path $HOME "count.log"; if (Test-Path -LiteralPath $p) { return @(Get-Content -LiteralPath $p).Count }; return 0 }'
    'function Get-Signal { [bool](Get-Variable -Name IddPwshProfileLoaded -Scope Global -ValueOnly -ErrorAction SilentlyContinue) }'
  )
}

Describe 'link-powershell-profile loader texts (once per startup)' {

  BeforeEach {
    $script:Result = Join-Path $TestDrive ('result-' + [guid]::NewGuid().ToString('N') + '.json')
  }

  It 'sources the config profile once when AllHosts then host run in one process' {
    $homeDir = New-ConfigHome
    $child = New-ChildScript (
      $script:Prelude + @(
        ". '$script:AllHostsPath'"
        ". '$script:HostPath'"
        "(Get-Count) | Set-Content -LiteralPath '$script:Result'"
      ))
    Invoke-Child -ScriptPath $child -HomeDir $homeDir
    (Get-Content -LiteralPath $script:Result) | Should -Be '1'
  }

  It 'sources the config profile once when the host text runs alone' {
    $homeDir = New-ConfigHome
    $child = New-ChildScript (
      $script:Prelude + @(
        ". '$script:HostPath'"
        "(Get-Count) | Set-Content -LiteralPath '$script:Result'"
      ))
    Invoke-Child -ScriptPath $child -HomeDir $homeDir
    (Get-Content -LiteralPath $script:Result) | Should -Be '1'
  }

  It 'sources the config profile twice when AllHosts is dot-sourced twice' {
    $homeDir = New-ConfigHome
    $child = New-ChildScript (
      $script:Prelude + @(
        ". '$script:AllHostsPath'"
        ". '$script:AllHostsPath'"
        "(Get-Count) | Set-Content -LiteralPath '$script:Result'"
      ))
    Invoke-Child -ScriptPath $child -HomeDir $homeDir
    (Get-Content -LiteralPath $script:Result) | Should -Be '2'
  }

  It 'keeps the signal unset after a throwing AllHosts source, and the host text then loads the profile' {
    $homeDir = New-ConfigHome
    $null = New-Item -ItemType File -Path (Join-Path $homeDir 'throw-once')
    $child = New-ChildScript (
      $script:Prelude + @(
        "try { . '$script:AllHostsPath' } catch { }"
        '$checkSignal = Get-Signal'
        '$checkCount = Get-Count'
        ". '$script:HostPath'"
        '$finalSignal = Get-Signal'
        '$finalCount = Get-Count'
        "[ordered]@{ checkSignal = `$checkSignal; checkCount = `$checkCount; finalSignal = `$finalSignal; finalCount = `$finalCount } | ConvertTo-Json | Set-Content -LiteralPath '$script:Result'"
      ))
    Invoke-Child -ScriptPath $child -HomeDir $homeDir
    $state = Get-Content -LiteralPath $script:Result -Raw | ConvertFrom-Json
    $state.checkSignal | Should -BeFalse
    $state.finalSignal | Should -BeTrue
    $state.finalCount | Should -Be ($state.checkCount + 1)
  }

  It 'keeps the signal unset after a throwing host source' {
    $homeDir = New-ConfigHome
    $null = New-Item -ItemType File -Path (Join-Path $homeDir 'throw-once')
    $child = New-ChildScript (
      $script:Prelude + @(
        "try { . '$script:HostPath' } catch { }"
        "[ordered]@{ signal = (Get-Signal) } | ConvertTo-Json | Set-Content -LiteralPath '$script:Result'"
      ))
    Invoke-Child -ScriptPath $child -HomeDir $homeDir
    $state = Get-Content -LiteralPath $script:Result -Raw | ConvertFrom-Json
    $state.signal | Should -BeFalse
  }

  It 'does not export the signal as an environment variable' {
    $homeDir = New-ConfigHome
    $child = New-ChildScript (
      $script:Prelude + @(
        ". '$script:AllHostsPath'"
        "`$inner = & '$script:Pwsh' -NoProfile -NonInteractive -Command `"[Environment]::GetEnvironmentVariable('IddPwshProfileLoaded')`""
        "[ordered]@{ own = [Environment]::GetEnvironmentVariable('IddPwshProfileLoaded'); child = `"`$inner`"; signal = (Get-Signal) } | ConvertTo-Json | Set-Content -LiteralPath '$script:Result'"
      ))
    Invoke-Child -ScriptPath $child -HomeDir $homeDir
    $state = Get-Content -LiteralPath $script:Result -Raw | ConvertFrom-Json
    $state.signal | Should -BeTrue
    $state.own | Should -BeNullOrEmpty
    $state.child | Should -BeNullOrEmpty
  }

  It 'maps profile.ps1 to the AllHosts text and both host names to the host text' {
    $script:Raw | Should -Match "'profile\.ps1'\s*=\s*\`$loaderAllHosts"
    $script:Raw | Should -Match "'Microsoft\.PowerShell_profile\.ps1'\s*=\s*\`$loaderHost"
    $script:Raw | Should -Match "'Microsoft\.VSCode_profile\.ps1'\s*=\s*\`$loaderHost"
    $script:Raw | Should -Match "@\('PowerShell', 'WindowsPowerShell'\)"
  }

  It 'uses no PowerShell 7-only syntax in the generated texts' {
    foreach ($name in 'loaderAllHosts', 'loaderHost') {
      Get-HereText $name | Should -Not -Match '\?\?|\?\.|&&|\|\|'
    }
  }
}

Describe 'link-powershell-profile linker body (Windows)' -Skip:($IsWindows -eq $false) {

  BeforeAll {
    # The body is the template text between the if-line and the end tag.
    # The template delimiters sit in comment lines, so the body parses as-is.
    $marker = '<%- if eq .chezmoi.os "windows" %>'
    $start = $script:Raw.IndexOf($marker)
    $start = $script:Raw.IndexOf("`n", $start) + 1
    $end = $script:Raw.LastIndexOf('<% end -%>')
    $body = $script:Raw.Substring($start, $end - $start)
    $script:BodyPath = Join-Path $TestDrive 'linker-body.ps1'
    Set-Content -LiteralPath $script:BodyPath -Value $body -Encoding utf8

    $script:ExpectedAll = (Get-HereText 'loaderAllHosts').Trim()
    $script:ExpectedHost = (Get-HereText 'loaderHost').Trim()

    # Run the body through -Command: -File drops array elements after the first.
    # The exit code is the body's own exit status, or 0 when it returns normally.
    function script:Invoke-Linker {
      param([string[]]$Roots)
      $quoted = @($Roots | ForEach-Object { "'" + $_.Replace("'", "''") + "'" })
      $bodyLiteral = $script:BodyPath.Replace("'", "''")
      $command = "& '$bodyLiteral' -ProfileRoot @($($quoted -join ',')); " +
        'exit $(if ($LASTEXITCODE) { $LASTEXITCODE } else { 0 })'
      & $script:Pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $command | Out-Null
      return $LASTEXITCODE
    }

    function script:New-TestRoot {
      $root = Join-Path $TestDrive ('root-' + [guid]::NewGuid().ToString('N'))
      $null = New-Item -ItemType Directory -Path $root -Force
      return $root
    }

    function script:Read-Trimmed([string]$Path) {
      return (Get-Content -LiteralPath $Path -Raw).Trim()
    }

    function script:New-TestTarget([string]$Content) {
      $target = Join-Path $TestDrive ('target-' + [guid]::NewGuid().ToString('N') + '.ps1')
      Set-Content -LiteralPath $target -Value $Content
      return $target
    }
  }

  It 'parses as PowerShell with no errors' {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
      $script:BodyPath, [ref]$tokens, [ref]$errors)
    $errors | Should -BeNullOrEmpty
  }

  It 'writes the mapped texts into two temporary roots' {
    $a = New-TestRoot
    $b = New-TestRoot
    Invoke-Linker -Roots @($a, $b) | Should -Be 0
    foreach ($root in @($a, $b)) {
      Read-Trimmed (Join-Path $root 'profile.ps1') | Should -Be $script:ExpectedAll
      Read-Trimmed (Join-Path $root 'Microsoft.PowerShell_profile.ps1') | Should -Be $script:ExpectedHost
      Read-Trimmed (Join-Path $root 'Microsoft.VSCode_profile.ps1') | Should -Be $script:ExpectedHost
    }
  }

  It 'replaces a regular file, creates missing names, and keeps a sibling file' {
    $a = New-TestRoot
    Set-Content -LiteralPath (Join-Path $a 'profile.ps1') -Value 'old'
    Set-Content -LiteralPath (Join-Path $a 'extra.ps1') -Value 'sibling'
    Invoke-Linker -Roots @($a) | Should -Be 0
    Read-Trimmed (Join-Path $a 'profile.ps1') | Should -Be $script:ExpectedAll
    Test-Path -LiteralPath (Join-Path $a 'Microsoft.VSCode_profile.ps1') | Should -BeTrue
    Read-Trimmed (Join-Path $a 'extra.ps1') | Should -Be 'sibling'
    @(Get-ChildItem -LiteralPath $a -Filter '*.tmp-*' -Force).Count | Should -Be 0
    @(Get-ChildItem -LiteralPath $a -Filter '*.bak' -Force).Count | Should -Be 0
  }

  It 'refuses a symbolic link, leaves its target alone, and still writes the other names and roots' {
    $a = New-TestRoot
    $b = New-TestRoot
    $target = New-TestTarget 'keep'
    $null = New-Item -ItemType SymbolicLink -Path (Join-Path $a 'profile.ps1') -Target $target
    Invoke-Linker -Roots @($a, $b) | Should -Be 1
    (Get-Item -LiteralPath (Join-Path $a 'profile.ps1') -Force).LinkType | Should -Be 'SymbolicLink'
    Read-Trimmed $target | Should -Be 'keep'
    Read-Trimmed (Join-Path $a 'Microsoft.VSCode_profile.ps1') | Should -Be $script:ExpectedHost
    Read-Trimmed (Join-Path $b 'profile.ps1') | Should -Be $script:ExpectedAll
  }

  It 'refuses a junction, leaves its directory alone, and still writes the other names and roots' {
    $a = New-TestRoot
    $b = New-TestRoot
    $dirTarget = Join-Path $TestDrive ('dir-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $dirTarget
    Set-Content -LiteralPath (Join-Path $dirTarget 'keep.txt') -Value 'keep'
    $null = New-Item -ItemType Junction -Path (Join-Path $a 'Microsoft.PowerShell_profile.ps1') -Target $dirTarget
    Invoke-Linker -Roots @($a, $b) | Should -Be 1
    (Get-Item -LiteralPath (Join-Path $a 'Microsoft.PowerShell_profile.ps1') -Force).LinkType | Should -Be 'Junction'
    Read-Trimmed (Join-Path $dirTarget 'keep.txt') | Should -Be 'keep'
    Read-Trimmed (Join-Path $a 'profile.ps1') | Should -Be $script:ExpectedAll
    Read-Trimmed (Join-Path $b 'Microsoft.VSCode_profile.ps1') | Should -Be $script:ExpectedHost
  }

  It 'refuses a file with more than one hard link and leaves it unchanged' {
    $a = New-TestRoot
    $b = New-TestRoot
    $target = New-TestTarget 'keep'
    $null = New-Item -ItemType HardLink -Path (Join-Path $a 'Microsoft.VSCode_profile.ps1') -Target $target
    Invoke-Linker -Roots @($a, $b) | Should -Be 1
    Read-Trimmed $target | Should -Be 'keep'
    Read-Trimmed (Join-Path $a 'Microsoft.VSCode_profile.ps1') | Should -Be 'keep'
    Read-Trimmed (Join-Path $a 'profile.ps1') | Should -Be $script:ExpectedAll
    Read-Trimmed (Join-Path $b 'Microsoft.PowerShell_profile.ps1') | Should -Be $script:ExpectedHost
  }

  It 'records a failed write, keeps the directory, and still writes the other names and roots' {
    $a = New-TestRoot
    $b = New-TestRoot
    $blocked = Join-Path $a 'profile.ps1'
    $null = New-Item -ItemType Directory -Path $blocked
    Set-Content -LiteralPath (Join-Path $blocked 'inside.txt') -Value 'inside'
    Invoke-Linker -Roots @($a, $b) | Should -Be 1
    Test-Path -LiteralPath $blocked -PathType Container | Should -BeTrue
    Read-Trimmed (Join-Path $blocked 'inside.txt') | Should -Be 'inside'
    Read-Trimmed (Join-Path $a 'Microsoft.PowerShell_profile.ps1') | Should -Be $script:ExpectedHost
    Read-Trimmed (Join-Path $b 'profile.ps1') | Should -Be $script:ExpectedAll
  }
}
