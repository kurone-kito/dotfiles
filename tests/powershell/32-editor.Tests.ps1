# Tests for the cross-platform EDITOR/VISUAL default (conf.d/32-editor.ps1).
# The real Get-Command is used, with no mock, so the function and alias cases
# exercise real PowerShell command resolution: each test narrows PATH to its
# own empty directory (only around the dot-source of the script) and puts
# stub applications in it. The script must work in Windows PowerShell 5.1 and
# 7, so this file avoids PowerShell 7-only syntax too. The shell counterpart
# is tests/bash/62-editor.bats.
# cspell:words PSCommandPath PSScriptRoot

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
  $psRoot = Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell'
  $script:ConfDir = Join-Path $psRoot 'conf.d'
  $script:Subject = Join-Path $script:ConfDir '32-editor.ps1'
  $script:OnWindows = ($IsWindows -ne $false)

  # A stand-in application: <name>.cmd on Windows (found through PATHEXT) and
  # an executable file elsewhere (an Application lookup needs the exec bit).
  function New-AppStub {
    param([string] $Dir, [string] $Name)

    if ($script:OnWindows) {
      $path = Join-Path $Dir "$Name.cmd"
      [System.IO.File]::WriteAllText($path, "@echo off`r`nexit /b 0`r`n")
    } else {
      $path = Join-Path $Dir $Name
      [System.IO.File]::WriteAllText($path, "#!/bin/sh`nexit 0`n")
      & chmod +x $path
      if ($LASTEXITCODE -ne 0) {
        throw "chmod +x failed for $path"
      }
    }
  }

  # Dot-source the script with PATH narrowed to $Dir for the call only, so the
  # test body and Pester keep a normal PATH.
  function Invoke-Subject {
    param([string] $Dir)

    $savedPath = $env:PATH
    try {
      $env:PATH = $Dir
      . $script:Subject
    } finally {
      $env:PATH = $savedPath
    }
  }
}

Describe '32-editor' {

  BeforeEach {
    $script:Saved = @{}
    foreach ($name in @('EDITOR', 'VISUAL')) {
      $script:Saved[$name] = [Environment]::GetEnvironmentVariable($name)
      [Environment]::SetEnvironmentVariable($name, $null)
    }

    # A fresh directory every time, so nothing from an earlier case (or from
    # command-discovery caching) can be found.
    $script:Dir = (New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))).FullName
  }

  # The test functions and aliases below are created in the scope of their own
  # It block and vanish with it, so no cleanup is needed (or wanted: removing
  # `nvim` or `edit` by name could delete a command the caller's session
  # already had).
  AfterEach {
    foreach ($name in @('EDITOR', 'VISUAL')) {
      [Environment]::SetEnvironmentVariable($name, $script:Saved[$name])
    }
  }

  Context 'with nvim' {
    It 'sets both variables to nvim' {
      New-AppStub -Dir $script:Dir -Name 'nvim'

      Invoke-Subject -Dir $script:Dir

      $env:EDITOR | Should -BeExactly 'nvim'
      $env:VISUAL | Should -BeExactly 'nvim'
    }

    It 'replaces preset values' {
      $env:EDITOR = 'emacs'
      $env:VISUAL = 'code'
      New-AppStub -Dir $script:Dir -Name 'nvim'

      Invoke-Subject -Dir $script:Dir

      $env:EDITOR | Should -BeExactly 'nvim'
      $env:VISUAL | Should -BeExactly 'nvim'
    }

    It 'prefers nvim when edit is present too' {
      New-AppStub -Dir $script:Dir -Name 'nvim'
      New-AppStub -Dir $script:Dir -Name 'edit'

      Invoke-Subject -Dir $script:Dir

      $env:EDITOR | Should -BeExactly 'nvim'
      $env:VISUAL | Should -BeExactly 'nvim'
    }
  }

  Context 'with neither nvim nor edit' {
    It 'keeps preset values' {
      $env:EDITOR = 'emacs'
      $env:VISUAL = 'code'

      Invoke-Subject -Dir $script:Dir

      $env:EDITOR | Should -BeExactly 'emacs'
      $env:VISUAL | Should -BeExactly 'code'
    }

    It 'leaves unset variables unset' {
      Invoke-Subject -Dir $script:Dir

      [Environment]::GetEnvironmentVariable('EDITOR') | Should -BeNullOrEmpty
      [Environment]::GetEnvironmentVariable('VISUAL') | Should -BeNullOrEmpty
    }
  }

  Context 'a function or alias is not an application' {
    It 'does not count the <Kind> named nvim' -ForEach @(
      @{ Kind = 'function' }
      @{ Kind = 'alias' }
    ) {
      if ($Kind -eq 'function') {
        Set-Item -Path Function:\nvim -Value { 'a function, not an application' }
      } else {
        Set-Alias -Name nvim -Value Get-Date
      }
      # Not vacuous: an unrestricted lookup does resolve it.
      (Get-Command nvim -ErrorAction Stop).CommandType | Should -BeIn @('Function', 'Alias')

      Invoke-Subject -Dir $script:Dir

      [Environment]::GetEnvironmentVariable('EDITOR') | Should -BeNullOrEmpty
      [Environment]::GetEnvironmentVariable('VISUAL') | Should -BeNullOrEmpty
    }
  }

  # The edit fallback exists on Windows only.
  Context 'on Windows' -Skip:($IsWindows -eq $false) {
    It 'falls back to edit when nvim is absent' {
      New-AppStub -Dir $script:Dir -Name 'edit'

      Invoke-Subject -Dir $script:Dir

      $env:EDITOR | Should -BeExactly 'edit'
      $env:VISUAL | Should -BeExactly 'edit'
    }

    It 'replaces preset values with edit' {
      $env:EDITOR = 'emacs'
      $env:VISUAL = 'code'
      New-AppStub -Dir $script:Dir -Name 'edit'

      Invoke-Subject -Dir $script:Dir

      $env:EDITOR | Should -BeExactly 'edit'
      $env:VISUAL | Should -BeExactly 'edit'
    }

    It 'does not count the <Kind> named edit' -ForEach @(
      @{ Kind = 'function' }
      @{ Kind = 'alias' }
    ) {
      if ($Kind -eq 'function') {
        Set-Item -Path Function:\edit -Value { 'a function, not an application' }
      } else {
        Set-Alias -Name edit -Value Get-Date
      }
      (Get-Command edit -ErrorAction Stop).CommandType | Should -BeIn @('Function', 'Alias')

      Invoke-Subject -Dir $script:Dir

      [Environment]::GetEnvironmentVariable('EDITOR') | Should -BeNullOrEmpty
      [Environment]::GetEnvironmentVariable('VISUAL') | Should -BeNullOrEmpty
    }
  }

  Context 'on a non-Windows host' -Skip:($IsWindows -ne $false) {
    It 'does not fall back to edit' {
      New-AppStub -Dir $script:Dir -Name 'edit'

      Invoke-Subject -Dir $script:Dir

      [Environment]::GetEnvironmentVariable('EDITOR') | Should -BeNullOrEmpty
      [Environment]::GetEnvironmentVariable('VISUAL') | Should -BeNullOrEmpty
    }
  }

  Context 'profile scope' {
    # The script is dot-sourced directly, as the profile loader does, and the
    # sorted variable and function names are compared before and after. Names,
    # not values: automatic variables change between snapshots. A no-op script
    # is dot-sourced first so that names the engine adds for any dot-sourced
    # file (PSCommandPath, PSScriptRoot, args, input) exist in both snapshots,
    # and the snapshot variables are created up front for the same reason.
    It 'leaks no variable or function when the script runs' {
      $leakNoop = Join-Path $script:Dir 'noop.ps1'
      Set-Content -LiteralPath $leakNoop -Value '$null = 1'
      New-AppStub -Dir $script:Dir -Name 'nvim'
      $leakSavedPath = $env:PATH
      $leakBeforeVars = $null
      $leakBeforeFns = $null
      $leakAfterVars = $null
      $leakAfterFns = $null
      . $leakNoop

      $leakBeforeVars = @(Get-Variable | Select-Object -ExpandProperty Name | Sort-Object)
      $leakBeforeFns = @(Get-ChildItem Function:\ | Select-Object -ExpandProperty Name | Sort-Object)
      try {
        $env:PATH = $script:Dir
        . $script:Subject
      } finally {
        $env:PATH = $leakSavedPath
      }
      $leakAfterVars = @(Get-Variable | Select-Object -ExpandProperty Name | Sort-Object)
      $leakAfterFns = @(Get-ChildItem Function:\ | Select-Object -ExpandProperty Name | Sort-Object)

      # The script really ran: the only observable change is the environment.
      $env:EDITOR | Should -BeExactly 'nvim'
      $env:VISUAL | Should -BeExactly 'nvim'
      $varDiff = @(Compare-Object $leakBeforeVars $leakAfterVars | ForEach-Object { $_.InputObject })
      $fnDiff = @(Compare-Object $leakBeforeFns $leakAfterFns | ForEach-Object { $_.InputObject })
      ($varDiff -join ', ') | Should -BeNullOrEmpty
      ($fnDiff -join ', ') | Should -BeNullOrEmpty
    }

    It 'sees no difference for a script that does nothing (negative control)' {
      $leakNoop = Join-Path $script:Dir 'noop.ps1'
      Set-Content -LiteralPath $leakNoop -Value '$null = 1'
      $leakBeforeVars = $null
      $leakBeforeFns = $null
      $leakAfterVars = $null
      $leakAfterFns = $null
      . $leakNoop

      $leakBeforeVars = @(Get-Variable | Select-Object -ExpandProperty Name | Sort-Object)
      $leakBeforeFns = @(Get-ChildItem Function:\ | Select-Object -ExpandProperty Name | Sort-Object)
      . $leakNoop
      $leakAfterVars = @(Get-Variable | Select-Object -ExpandProperty Name | Sort-Object)
      $leakAfterFns = @(Get-ChildItem Function:\ | Select-Object -ExpandProperty Name | Sort-Object)

      @(Compare-Object $leakBeforeVars $leakAfterVars).Count | Should -Be 0
      @(Compare-Object $leakBeforeFns $leakAfterFns).Count | Should -Be 0
    }

    It 'reports a variable and a function that a script leaks (positive control)' {
      $leakNoop = Join-Path $script:Dir 'noop.ps1'
      Set-Content -LiteralPath $leakNoop -Value '$null = 1'
      $leakLeaky = Join-Path $script:Dir 'leaky.ps1'
      Set-Content -LiteralPath $leakLeaky -Value ('$leakedByControl = 1' + [Environment]::NewLine + 'function Leaked-ByControl { }')
      $leakBeforeVars = $null
      $leakBeforeFns = $null
      $leakAfterVars = $null
      $leakAfterFns = $null
      . $leakNoop

      $leakBeforeVars = @(Get-Variable | Select-Object -ExpandProperty Name | Sort-Object)
      $leakBeforeFns = @(Get-ChildItem Function:\ | Select-Object -ExpandProperty Name | Sort-Object)
      . $leakLeaky
      $leakAfterVars = @(Get-Variable | Select-Object -ExpandProperty Name | Sort-Object)
      $leakAfterFns = @(Get-ChildItem Function:\ | Select-Object -ExpandProperty Name | Sort-Object)

      $varDiff = @(Compare-Object $leakBeforeVars $leakAfterVars | ForEach-Object { $_.InputObject })
      $fnDiff = @(Compare-Object $leakBeforeFns $leakAfterFns | ForEach-Object { $_.InputObject })
      $varDiff | Should -Contain 'leakedByControl'
      $fnDiff | Should -Contain 'Leaked-ByControl'
    }
  }

  Context 'load order' {
    It 'sorts after 30-mise.ps1 and before 35-node-options.ps1' {
      $names = @(Get-ChildItem (Join-Path $script:ConfDir '*.ps1') |
          Sort-Object Name |
          Select-Object -ExpandProperty Name)
      $mise = [array]::IndexOf($names, '30-mise.ps1')
      $editor = [array]::IndexOf($names, '32-editor.ps1')
      $node = [array]::IndexOf($names, '35-node-options.ps1')

      $mise | Should -BeGreaterOrEqual 0
      $editor | Should -BeGreaterThan $mise
      $node | Should -BeGreaterThan $editor
    }
  }
}
