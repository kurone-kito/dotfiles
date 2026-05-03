# Tests for the PowerShell PATH reconciliation script.
# Exercises: stale managed-path cleanup, de-duplication, and idempotency.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '01-path.ps1'

  function New-ManagedPathLayout {
    $paths = [ordered]@{}

    $paths.WinGetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $paths.Zellij = Join-Path $env:LOCALAPPDATA 'Zellij'
    $paths.GnuWin32 = Join-Path ${env:ProgramFiles(x86)} 'GnuWin32\bin'
    $paths.HomeLocalBin = Join-Path $HOME '.local\bin'
    $paths.CurrentMiseBin = Join-Path (
      (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') 'jdx.mise_Microsoft.Winget.Source_test') 'mise')
    ) 'bin'
    $paths.StaleMiseBin = Join-Path (
      (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') 'jdx.mise_Microsoft.Winget.Source_stale') 'mise')
    ) 'bin'
    $paths.UnrelatedA = 'TestDrive:\unrelated-a'
    $paths.UnrelatedB = 'TestDrive:\unrelated-b'

    foreach ($managed in @(
      $paths.WinGetLinks
      $paths.Zellij
      $paths.GnuWin32
      $paths.HomeLocalBin
      $paths.CurrentMiseBin
    )) {
      New-Item -ItemType Directory -Path $managed -Force | Out-Null
    }

    return $paths
  }
}

Describe '01-path' -Skip:($IsWindows -eq $false) {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalPath = $env:PATH
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $script:OriginalProgramFilesX86 = ${env:ProgramFiles(x86)}

    $homeRoot = (New-Item -ItemType Directory -Path 'TestDrive:\home' -Force).FullName
    $localAppDataRoot = (New-Item -ItemType Directory -Path 'TestDrive:\LocalAppData' -Force).FullName
    $programFilesX86Root = (New-Item -ItemType Directory -Path 'TestDrive:\ProgramFilesX86' -Force).FullName

    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force
    $env:LOCALAPPDATA = $localAppDataRoot
    ${env:ProgramFiles(x86)} = $programFilesX86Root

    $script:Paths = New-ManagedPathLayout

    # Disable registry sync by default so existing tests are not
    # affected by the real Windows User PATH.
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = ''

    $env:PATH = @(
      $script:Paths.UnrelatedA
      $script:Paths.StaleMiseBin
      $script:Paths.WinGetLinks
      $script:Paths.UnrelatedB
      $script:Paths.WinGetLinks
    ) -join ';'
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:PATH = $script:OriginalPath
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
    ${env:ProgramFiles(x86)} = $script:OriginalProgramFilesX86

    Remove-Item Function:\Split-PathEntries -ErrorAction SilentlyContinue
    Remove-Item Function:\Normalize-PathEntry -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-StaticManagedPaths -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-MisePackagesRoot -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-MiseManagedPaths -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-IsManagedPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-RegistryUserPath -ErrorAction SilentlyContinue
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = $null
  }

  It 'reconciles managed entries and removes stale winget package paths' {
    . $script:Subject

    $env:PATH | Should -Be (@(
      $script:Paths.CurrentMiseBin
      $script:Paths.WinGetLinks
      $script:Paths.Zellij
      $script:Paths.GnuWin32
      $script:Paths.HomeLocalBin
      $script:Paths.UnrelatedA
      $script:Paths.UnrelatedB
    ) -join ';')
  }

  It 'is idempotent across repeated profile loads' {
    . $script:Subject
    $firstPath = $env:PATH

    . $script:Subject
    $secondPath = $env:PATH

    $secondPath | Should -Be $firstPath
  }

  Context 'registry User PATH sync' {

    It 'appends missing registry entries to the process PATH' {
      $registryOnly = 'TestDrive:\registry-only'
      New-Item -ItemType Directory -Path $registryOnly -Force | Out-Null

      $env:DOTFILES_TEST_REGISTRY_USER_PATH = @(
        $script:Paths.WinGetLinks
        $registryOnly
      ) -join ';'

      . $script:Subject

      $entries = $env:PATH -split ';'
      $entries | Should -Contain $registryOnly
    }

    It 'does not duplicate entries already present in PATH' {
      $env:DOTFILES_TEST_REGISTRY_USER_PATH = @(
        $script:Paths.UnrelatedA
        $script:Paths.WinGetLinks
      ) -join ';'

      . $script:Subject

      $entries = $env:PATH -split ';'
      $dupes = ($entries | Where-Object {
        $_ -eq $script:Paths.UnrelatedA
      }).Count
      $dupes | Should -Be 1
    }

    It 'skips registry entries whose directories do not exist' {
      $env:DOTFILES_TEST_REGISTRY_USER_PATH = 'TestDrive:\nonexistent-dir'

      . $script:Subject

      $env:PATH | Should -Not -Match 'nonexistent-dir'
    }

    It 'is idempotent with registry sync enabled' {
      $registryOnly = 'TestDrive:\registry-stable'
      New-Item -ItemType Directory -Path $registryOnly -Force | Out-Null

      $env:DOTFILES_TEST_REGISTRY_USER_PATH = $registryOnly

      . $script:Subject
      $firstPath = $env:PATH

      . $script:Subject
      $secondPath = $env:PATH

      $secondPath | Should -Be $firstPath
    }
  }
}
