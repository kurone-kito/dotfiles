# Tests for the Unix-pwsh Cargo PATH integration.
# Windows is covered by tests/powershell/01-path.Tests.ps1 because the
# Windows path is owned by Get-StaticManagedPaths in 01-path.ps1.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell/conf.d')
  ) '02-cargo.ps1'
}

Describe '02-cargo (Unix pwsh)' -Skip:($IsWindows -eq $true) {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalPath = $env:PATH
    $script:OriginalCargoHome = $env:CARGO_HOME

    # Use a resolved physical path. TestDrive:\... cannot be used as a
    # PATH entry on Unix because ":" is the PATH separator.
    $script:WorkRoot = (New-Item -ItemType Directory `
        -Path (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().Guid)) `
        -Force).FullName
    $homeRoot = (New-Item -ItemType Directory `
        -Path (Join-Path $script:WorkRoot 'home') -Force).FullName

    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force
    $env:CARGO_HOME = $null
    $env:PATH = '/usr/bin:/bin'
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:PATH = $script:OriginalPath
    $env:CARGO_HOME = $script:OriginalCargoHome
    Remove-Item -LiteralPath $script:WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'prepends $HOME/.cargo/bin when the directory exists' {
    $cargoBin = Join-Path (Join-Path $HOME '.cargo') 'bin'
    New-Item -ItemType Directory -Path $cargoBin -Force | Out-Null

    . $script:Subject

    $env:PATH.Split([IO.Path]::PathSeparator)[0] | Should -Be $cargoBin
  }

  It 'is a no-op when the cargo bin directory does not exist' {
    $before = $env:PATH
    . $script:Subject
    $env:PATH | Should -Be $before
  }

  It 'is idempotent across repeated sources' {
    $cargoBin = Join-Path (Join-Path $HOME '.cargo') 'bin'
    New-Item -ItemType Directory -Path $cargoBin -Force | Out-Null

    . $script:Subject
    $first = $env:PATH
    . $script:Subject
    $env:PATH | Should -Be $first
  }

  It 'honors $env:CARGO_HOME when set' {
    $altHome = (New-Item -ItemType Directory `
        -Path (Join-Path $script:WorkRoot 'cargo-alt') -Force).FullName
    $altBin = (New-Item -ItemType Directory `
        -Path (Join-Path $altHome 'bin') -Force).FullName
    $env:CARGO_HOME = $altHome

    . $script:Subject

    $env:PATH.Split([IO.Path]::PathSeparator)[0] | Should -Be $altBin
  }
}

Describe '02-cargo (PS5.1 $IsWindows guard)' {

  # $IsWindows is a ReadOnly, AllScope automatic variable: Set-Variable
  # -Force can override it, but AllScope means the override leaks
  # process-wide rather than staying scoped to a block. Simulate PS5.1
  # (where $IsWindows is $null) in a throwaway subprocess instead of
  # mutating the current Pester process.
  It 'returns before touching $env:PATH when $IsWindows is $null (PS5.1 emulation)' {
    # A real $HOME/.cargo/bin must exist so a wrongly-taken Unix branch
    # has something to prepend; otherwise the script's own "directory
    # missing" no-op would mask the guard bug and the test would pass
    # even against the pre-fix code.
    $home51 = (New-Item -ItemType Directory `
        -Path (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().Guid)) -Force).FullName
    New-Item -ItemType Directory -Path (Join-Path $home51 '.cargo/bin') -Force | Out-Null

    try {
      $cmd = "Set-Variable -Name IsWindows -Value `$null -Force; " +
        "Set-Variable -Name HOME -Value '$home51' -Force; " +
        "`$env:PATH = '/usr/bin:/bin'; `$before = `$env:PATH; . '$script:Subject'; " +
        "if (`$env:PATH -eq `$before) { 'UNCHANGED' } else { 'CHANGED' }"
      $result = (& pwsh -NoLogo -NoProfile -Command $cmd 2>&1 | Select-Object -Last 1)

      $result | Should -Be 'UNCHANGED'
    } finally {
      Remove-Item -LiteralPath $home51 -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
