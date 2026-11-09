# Tests for the PowerShell worktrunk initialization script.
# Exercises: early exit, command fallback, init evaluation, trailing-zero
# stripping, and cleanup.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '45-worktrunk.ps1'

  # Create a mock Application command that outputs given lines to stdout.
  # The production code invokes by resolved path, so tests need real files.
  function New-MockNativeCommand {
    param([string]$Dir, [string]$Name, [string[]]$Lines)
    $path = Join-Path $Dir "$Name.ps1"
    $body = "#!/usr/bin/env pwsh`n" + (
      ($Lines | ForEach-Object { "Write-Output '$($_ -replace "'", "''")'" }) -join "`n"
    ) + "`n"
    [System.IO.File]::WriteAllText($path, $body)
    return $path
  }
}

Describe '45-worktrunk' {

  BeforeEach {
    $script:MockBin = Join-Path ([System.IO.Path]::GetTempPath()) `
      "wt-mock-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $script:MockBin -Force | Out-Null

    Remove-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __wtExitOk -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __psi -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __proc -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __stderrTask -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkInitialized -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkCommand -Scope Script -ErrorAction SilentlyContinue

    Mock Get-Command { $null } -ParameterFilter { $Name -in @('git-wt', 'wt') }
  }

  AfterEach {
    Remove-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __wtExitOk -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __psi -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __proc -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __stderrTask -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkInitialized -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkCommand -Scope Script -ErrorAction SilentlyContinue
    if ($script:MockBin -and (Test-Path $script:MockBin)) {
      Remove-Item $script:MockBin -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It 'returns early without error when neither git-wt nor wt is available' {
    { . $script:Subject } | Should -Not -Throw
  }

  It 'evaluates init output when git-wt is available' {
    $mockPath = New-MockNativeCommand $script:MockBin 'git-wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "git-wt"'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'git-wt'
  }

  It 'falls back to wt when git-wt is not available' {
    $mockPath = New-MockNativeCommand $script:MockBin 'wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "wt"'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'wt'
  }

  It 'ignores function/alias named git-wt (only Application type accepted)' {
    # Default mock returns $null — no Application-type git-wt or wt exists.
    . $script:Subject

    $script:WorktrunkInitialized | Should -BeNullOrEmpty
    $script:WorktrunkCommand | Should -BeNullOrEmpty
  }

  It 'does not fall back to wt when wt resolves to Windows Terminal' {
    Mock Get-Command {
      [pscustomobject]@{
        Name = 'wt'
        CommandType = 'Application'
        Path = 'C:\Users\me\AppData\Local\Microsoft\WindowsApps\wt.exe'
      }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeNullOrEmpty
    $script:WorktrunkCommand | Should -BeNullOrEmpty
  }

  It 'skips Windows Terminal wt and uses worktrunk wt from later PATH entry' {
    $mockPath = New-MockNativeCommand $script:MockBin 'wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "wt"'
    )
    Mock Get-Command {
      @(
        [pscustomobject]@{
          Name = 'wt'; CommandType = 'Application'
          Path = 'C:\Users\me\AppData\Local\Microsoft\WindowsApps\wt.exe'
        },
        [pscustomobject]@{
          Name = 'wt'; CommandType = 'Application'
          Path = $mockPath
        }
      )
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'wt'
  }

  It 'prefers git-wt when both git-wt and wt are available' {
    $gitWtPath = New-MockNativeCommand $script:MockBin 'git-wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "git-wt"'
    )
    $wtPath = New-MockNativeCommand $script:MockBin 'wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "wt"'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $gitWtPath }
    } -ParameterFilter { $Name -eq 'git-wt' }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'wt'; CommandType = 'Application'; Path = $wtPath }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'git-wt'
  }

  It 'strips trailing zero lines from init output before evaluation' {
    $mockPath = New-MockNativeCommand $script:MockBin 'git-wt' @(
      '$script:WorktrunkInitialized = $true',
      '0'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
  }

  It 'strips output that is only a bare zero' {
    $mockPath = New-MockNativeCommand $script:MockBin 'git-wt' @('0')
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeNullOrEmpty
  }

  It 'cleans up temporary variables after execution' {
    $mockPath = New-MockNativeCommand $script:MockBin 'git-wt' @(
      '$script:WorktrunkInitialized = $true'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    Get-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __wtPath -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __wtCandidate -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __candidatePath -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __gitWtInfo -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __wtExitOk -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __psi -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __proc -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __stderrTask -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }

  Context 'the git-wt that mise resolved' {

    BeforeEach {
      Remove-Item Env:WORKTRUNK_BIN -ErrorAction SilentlyContinue
    }

    AfterEach {
      Remove-Item Env:WORKTRUNK_BIN -ErrorAction SilentlyContinue
    }

    It 'runs the init from the resolved git-wt rather than the PATH command' {
      $pathGitWt = New-MockNativeCommand $script:MockBin 'git-wt' @(
        '$script:WorktrunkCommand = "path"'
      )
      $resolvedGitWt = New-MockNativeCommand $script:MockBin 'resolved-git-wt' @(
        '$script:WorktrunkInitialized = $true',
        '$script:WorktrunkCommand = "resolved"'
      )
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $pathGitWt }
      } -ParameterFilter { $Name -eq 'git-wt' }
      $__miseExecutables = @{ 'git-wt' = $resolvedGitWt }

      . $script:Subject

      $script:WorktrunkCommand | Should -Be 'resolved'
    }

    It 'sets WORKTRUNK_BIN to the resolved git-wt only while the init is evaluated' {
      $resolvedGitWt = New-MockNativeCommand $script:MockBin 'resolved-git-wt' @(
        '$script:SeenWorktrunkBin = $env:WORKTRUNK_BIN'
      )
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $resolvedGitWt }
      } -ParameterFilter { $Name -eq 'git-wt' }
      $__miseExecutables = @{ 'git-wt' = $resolvedGitWt }

      . $script:Subject

      $script:SeenWorktrunkBin | Should -Be $resolvedGitWt
      $env:WORKTRUNK_BIN | Should -BeNullOrEmpty
    }

    It 'keeps a WORKTRUNK_BIN value that the user set' {
      $userValue = Join-Path $script:MockBin 'user-git-wt.exe'
      $resolvedGitWt = New-MockNativeCommand $script:MockBin 'resolved-git-wt' @(
        '$script:SeenWorktrunkBin = $env:WORKTRUNK_BIN'
      )
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $resolvedGitWt }
      } -ParameterFilter { $Name -eq 'git-wt' }
      $__miseExecutables = @{ 'git-wt' = $resolvedGitWt }
      $env:WORKTRUNK_BIN = $userValue

      . $script:Subject

      $script:SeenWorktrunkBin | Should -Be $userValue
      $env:WORKTRUNK_BIN | Should -Be $userValue
    }

    # Windows removes an environment variable that is assigned an empty string,
    # so an explicitly empty value can exist only off Windows.
    It 'keeps an explicitly empty WORKTRUNK_BIN that the user set' -Skip:($IsWindows -ne $false) {
      $resolvedGitWt = New-MockNativeCommand $script:MockBin 'resolved-git-wt' @(
        '$script:SeenWorktrunkBin = $env:WORKTRUNK_BIN'
      )
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $resolvedGitWt }
      } -ParameterFilter { $Name -eq 'git-wt' }
      $__miseExecutables = @{ 'git-wt' = $resolvedGitWt }
      $env:WORKTRUNK_BIN = ''

      . $script:Subject

      $script:SeenWorktrunkBin | Should -BeNullOrEmpty
    }

    It 'leaves WORKTRUNK_BIN unset and uses the PATH command when mise resolved no git-wt' {
      $pathGitWt = New-MockNativeCommand $script:MockBin 'git-wt' @(
        '$script:SeenWorktrunkBin = $env:WORKTRUNK_BIN',
        '$script:WorktrunkCommand = "path"'
      )
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $pathGitWt }
      } -ParameterFilter { $Name -eq 'git-wt' }
      $__miseExecutables = @{}

      . $script:Subject

      $script:WorktrunkCommand | Should -Be 'path'
      $script:SeenWorktrunkBin | Should -BeNullOrEmpty
      $env:WORKTRUNK_BIN | Should -BeNullOrEmpty
    }

    It 'removes the resolution variables after the init' {
      $resolvedGitWt = New-MockNativeCommand $script:MockBin 'resolved-git-wt' @(
        '$script:WorktrunkInitialized = $true'
      )
      Mock Get-Command {
        [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $resolvedGitWt }
      } -ParameterFilter { $Name -eq 'git-wt' }
      $__miseExecutables = @{ 'git-wt' = $resolvedGitWt }

      . $script:Subject

      Get-Variable __wtResolved -Scope Script -ErrorAction SilentlyContinue |
        Should -BeNullOrEmpty
      Get-Variable __wtSetBin -Scope Script -ErrorAction SilentlyContinue |
        Should -BeNullOrEmpty
    }
  }
}
