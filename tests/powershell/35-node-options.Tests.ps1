# Tests for the cross-platform NODE_OPTIONS default (conf.d/35-node-options.ps1).
# Runs the script through the real profile.ps1 conf.d loader against a
# TestDrive: home whose conf.d holds only a copy of the script, with a
# `Get-Command` mock that resolves a recording mock `node` (a real .ps1 file,
# as in 45-worktrunk.Tests.ps1). It covers the same merge, precedence,
# idempotence, inheritance, unavailable-runtime and no-evaluation contract as
# tests/bash/65-node-options.bats. The script must work in Windows PowerShell
# 5.1 and 7, so this file avoids PowerShell 7-only syntax too.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $psRoot = Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell'
  $script:Loader = Join-Path $psRoot 'profile.ps1'
  $script:Subject = Join-Path (Join-Path $psRoot 'conf.d') '35-node-options.ps1'
  $script:Option = '--network-family-autoselection-attempt-timeout'
  $script:Default = "$($script:Option)=2000"
  $script:Variables = @('NODE_OPTIONS', 'MISE_AUTO_INSTALL', 'MISE_EXEC_AUTO_INSTALL', 'MISE_OFFLINE')

  # The real Get-Command, captured before any mock replaces it.
  $script:RealGetCommand = Get-Command Get-Command -CommandType Cmdlet

  # The host's real node, if any, for the real-Node.js tests below.
  $script:RealNode = Get-Command node -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1

  # A real .ps1 stand-in for node: it records how it was called and exits
  # with the requested code.
  function New-NodeMock {
    param([string] $Dir, [string] $Log, [int] $ExitCode)

    $path = Join-Path $Dir 'node.ps1'
    $body = @'
$line = 'argv=' + ($args -join ' ') +
  ' NODE_OPTIONS=' + [Environment]::GetEnvironmentVariable('NODE_OPTIONS') +
  ' MISE_AUTO_INSTALL=' + [Environment]::GetEnvironmentVariable('MISE_AUTO_INSTALL') +
  ' MISE_EXEC_AUTO_INSTALL=' + [Environment]::GetEnvironmentVariable('MISE_EXEC_AUTO_INSTALL') +
  ' MISE_OFFLINE=' + [Environment]::GetEnvironmentVariable('MISE_OFFLINE')
Add-Content -LiteralPath '__LOG__' -Value $line
exit __EXIT__
'@
    $body = $body.Replace('__LOG__', $Log).Replace('__EXIT__', [string]$ExitCode)
    [System.IO.File]::WriteAllText($path, $body)
    return $path
  }
}

Describe '35-node-options' {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:Saved = @{}
    foreach ($name in $script:Variables) {
      $script:Saved[$name] = [Environment]::GetEnvironmentVariable($name)
      [Environment]::SetEnvironmentVariable($name, $null)
    }

    $homeRoot = (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'home') -Force).FullName
    $confDir = Join-Path (Join-Path (Join-Path $homeRoot '.config') 'powershell') 'conf.d'
    New-Item -ItemType Directory -Path $confDir -Force | Out-Null
    Copy-Item -LiteralPath $script:Subject -Destination $confDir
    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force

    # Keep the loader's prompt section inert.
    Set-Item Function:\starship { '' }
    Set-Item Function:\zoxide { '' }
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    $script:MockDir = (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'bin') -Force).FullName
    $script:Log = Join-Path $TestDrive 'node-mock.log'
    New-Item -ItemType File -Path $script:Log -Force | Out-Null
    $script:NodePath = New-NodeMock -Dir $script:MockDir -Log $script:Log -ExitCode 0

    # Pester 6 throws for a call that no filtered mock matches, so forward
    # every other lookup (the loader asks for starship and zoxide) to the
    # real cmdlet, invoked through the CommandInfo captured in BeforeAll
    # (a name, even module-qualified, would hit the mock again).
    Mock Get-Command { & $script:RealGetCommand @PesterBoundParameters }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'node'; CommandType = 'Application'; Path = $script:NodePath }
    } -ParameterFilter { $Name -eq 'node' }
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    foreach ($name in $script:Variables) {
      [Environment]::SetEnvironmentVariable($name, $script:Saved[$name])
    }
    foreach ($name in @('starship', 'zoxide', 'Test-DotfilesPSReadLineReady', 'node')) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  Context 'merging' {
    It 'exports the default when NODE_OPTIONS is unset' {
      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly $script:Default
    }

    It 'exports the default when NODE_OPTIONS is empty' {
      $env:NODE_OPTIONS = ''

      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly $script:Default
    }

    It 'keeps unrelated options and appends the default once, after them' {
      $env:NODE_OPTIONS = '--max-old-space-size=4096 --trace-warnings'

      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly "--max-old-space-size=4096 --trace-warnings $($script:Default)"
    }

    It 'leaves an explicit value untouched: <Value>' -ForEach @(
      @{ Value = '--network-family-autoselection-attempt-timeout=5000' }
      @{ Value = '--network-family-autoselection-attempt-timeout 5000' }
      @{ Value = '"--network-family-autoselection-attempt-timeout=5000"' }
      @{ Value = '"--network-family-autoselection-attempt-timeout" 5000' }
      @{ Value = '--network_family_autoselection_attempt_timeout=5000' }
      @{ Value = '--network-family_autoselection-attempt_timeout 5000' }
      @{ Value = '--max-old-space-size=4096 --network-family-autoselection-attempt-timeout=5000 --trace-warnings' }
      @{ Value = '--network-family-autoselection-attempt-timeout="5000"' }
      @{ Value = '"--network-family-autoselection-attempt-timeout"=5000' }
    ) {
      $env:NODE_OPTIONS = $Value

      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly $Value
    }

    It 'appends the default after an input that does not name the exact option: <Value>' -ForEach @(
      @{ Value = '--max-old-space-size=4096' }
      @{ Value = '--network-family-autoselection' }
      @{ Value = '--no-network-family-autoselection' }
      @{ Value = '--Network-Family-Autoselection-Attempt-Timeout=1' }
      @{ Value = '--require "/tmp/a b/x.js"' }
      @{ Value = '--require "/tmp/--network-family-autoselection-attempt-timeout=1/x.js"' }
      @{ Value = "--require 'single quoted'" }
      @{ Value = '--require="a b.js"' }
      @{ Value = '""' }
      @{ Value = "--max-old-space-size=1`t--network-family-autoselection-attempt-timeout=3" }
      @{ Value = '--require "a\"b" --max-old-space-size=1' }
    ) {
      $env:NODE_OPTIONS = $Value

      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly "$Value $($script:Default)"
    }

    It 'leaves a malformed value untouched: <Value>' -ForEach @(
      @{ Value = '--max-old-space-size=4096 "unterminated' }
      @{ Value = '"ends with escape\' }
    ) {
      $env:NODE_OPTIONS = $Value

      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly $Value
    }

    It 'keeps exactly one copy when the loader runs twice' {
      . $script:Loader
      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly $script:Default
    }

    It 'is inherited by a child process' {
      . $script:Loader

      # No double quotes in the argument: Windows PowerShell 5.1 strips them
      # when it hands a string to a native command.
      $hostPath = (Get-Process -Id $PID).Path
      $childOutput = & $hostPath -NoProfile -Command '$env:NODE_OPTIONS'

      $childOutput | Should -BeExactly $script:Default
    }
  }

  Context 'no evaluation' {
    It 'never evaluates command text found in NODE_OPTIONS' {
      $sentinel = Join-Path $TestDrive 'pwned'
      $value = "--require `"`$(New-Item -ItemType File '$sentinel')`" ; `` * & | ~ `$HOME"
      $env:NODE_OPTIONS = $value

      . $script:Loader

      Test-Path -LiteralPath $sentinel | Should -BeFalse
      $env:NODE_OPTIONS | Should -BeExactly "$value $($script:Default)"
    }
  }

  Context 'the node it probes' {
    It 'leaves the environment untouched when no node is on PATH' {
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'node' }
      $env:NODE_OPTIONS = '--max-old-space-size=4096'

      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly '--max-old-space-size=4096'
      Get-Content -LiteralPath $script:Log | Should -BeNullOrEmpty
    }

    It 'only ever asks for an Application named node, so a function cannot be run' {
      Set-Item Function:\node { throw 'the function node must never run' }

      . $script:Loader

      Should -Invoke Get-Command -ParameterFilter {
        $Name -eq 'node' -and $CommandType -eq 'Application'
      }
      $env:NODE_OPTIONS | Should -BeExactly $script:Default
    }

    It 'leaves the environment untouched when node rejects the option (exit 9)' {
      New-NodeMock -Dir $script:MockDir -Log $script:Log -ExitCode 9 | Out-Null

      . $script:Loader

      [Environment]::GetEnvironmentVariable('NODE_OPTIONS') | Should -BeNullOrEmpty
    }

    It 'leaves the environment untouched when node fails (exit 1)' {
      New-NodeMock -Dir $script:MockDir -Log $script:Log -ExitCode 1 | Out-Null
      $env:NODE_OPTIONS = '--max-old-space-size=4096'

      . $script:Loader

      $env:NODE_OPTIONS | Should -BeExactly '--max-old-space-size=4096'
    }

    It 'probes with a non-empty script, only the option, and the mise guards' {
      $env:NODE_OPTIONS = '--max-old-space-size=4096'

      . $script:Loader

      Get-Content -LiteralPath $script:Log |
        Should -BeExactly "argv=-e 0 NODE_OPTIONS=$($script:Default) MISE_AUTO_INSTALL=0 MISE_EXEC_AUTO_INSTALL=0 MISE_OFFLINE=1"
    }

    It 'does not probe when the option is already present' {
      $env:NODE_OPTIONS = "$($script:Option)=5000"

      . $script:Loader

      Get-Content -LiteralPath $script:Log | Should -BeNullOrEmpty
    }

    It 'restores every variable it touched, removing the ones that were absent' {
      New-NodeMock -Dir $script:MockDir -Log $script:Log -ExitCode 9 | Out-Null
      $env:MISE_OFFLINE = 'kept'

      . $script:Loader

      [Environment]::GetEnvironmentVariable('NODE_OPTIONS') | Should -BeNullOrEmpty
      [Environment]::GetEnvironmentVariable('MISE_AUTO_INSTALL') | Should -BeNullOrEmpty
      [Environment]::GetEnvironmentVariable('MISE_EXEC_AUTO_INSTALL') | Should -BeNullOrEmpty
      [Environment]::GetEnvironmentVariable('MISE_OFFLINE') | Should -BeExactly 'kept'
    }

    It 'keeps the caller''s $LASTEXITCODE' {
      $global:LASTEXITCODE = 42

      . $script:Loader

      $global:LASTEXITCODE | Should -Be 42
    }

    It 'defines nothing in the profile scope' {
      . $script:Loader

      Get-Command Split-NodeOptions -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
      Get-Command Test-NodeOptionToken -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
  }

  Context 'with the host Node.js' {
    BeforeEach {
      $script:HostNodeUsable = $false
      if ($null -ne $script:RealNode) {
        $probePath = if ($script:RealNode.Path) { $script:RealNode.Path } else { $script:RealNode.Source }
        $before = [Environment]::GetEnvironmentVariable('NODE_OPTIONS')
        try {
          [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $script:Default)
          & $probePath -e 0 2>$null | Out-Null
          $script:HostNodeUsable = ($LASTEXITCODE -eq 0)
          $script:HostNodePath = $probePath
        } finally {
          [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $before)
        }
      }
      if ($script:HostNodeUsable) {
        Mock Get-Command {
          [pscustomobject]@{ Name = 'node'; CommandType = 'Application'; Path = $script:HostNodePath }
        } -ParameterFilter { $Name -eq 'node' }
      }
    }

    It 'reports 2000 from net.getDefaultAutoSelectFamilyAttemptTimeout()' {
      if (-not $script:HostNodeUsable) {
        Set-ItResult -Skipped -Because 'the host node is missing or rejects the option'
        return
      }

      . $script:Loader

      (& $script:HostNodePath -p 'net.getDefaultAutoSelectFamilyAttemptTimeout()') | Should -BeExactly '2000'
    }

    It 'keeps an explicitly supplied alternative effective' {
      if (-not $script:HostNodeUsable) {
        Set-ItResult -Skipped -Because 'the host node is missing or rejects the option'
        return
      }
      $env:NODE_OPTIONS = "$($script:Option)=500"

      . $script:Loader

      (& $script:HostNodePath -p 'net.getDefaultAutoSelectFamilyAttemptTimeout()') | Should -BeExactly '500'
    }
  }
}
