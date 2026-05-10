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
