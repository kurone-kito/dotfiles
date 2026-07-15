# Parity test: conf.d/01-path.ps1 (session PATH) and the User-PATH
# registry writer (run_onchange_after_35-register-path.ps1.tmpl,
# exercised here via its pre-rendered fixture) must compute the
# identical managed-path set. Both surfaces are meant to consume the
# single shared source in lib/managed-paths.ps1 — this test fails if
# the fixture's embedded copy ever drifts from that file, or if
# either surface stops consuming it and reintroduces a hand-written
# list.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:ConfDScript = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '01-path.ps1'
  $script:RegisterFixture = Join-Path $PSScriptRoot 'fixtures/35-register-path.ps1'

  function New-ManagedPathLayout {
    $paths = [ordered]@{}

    $paths.WinGetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $paths.Zellij = Join-Path $env:LOCALAPPDATA 'Zellij'
    $paths.GnuWin32 = Join-Path ${env:ProgramFiles(x86)} 'GnuWin32\bin'
    $paths.HomeLocalBin = Join-Path $HOME '.local\bin'
    $paths.HomeCargoBin = Join-Path $HOME '.cargo\bin'
    $paths.CurrentMiseBin = Join-Path (
      (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') 'jdx.mise_Microsoft.Winget.Source_test') 'mise')
    ) 'bin'

    foreach ($managed in @(
      $paths.WinGetLinks
      $paths.Zellij
      $paths.GnuWin32
      $paths.HomeLocalBin
      $paths.HomeCargoBin
      $paths.CurrentMiseBin
    )) {
      New-Item -ItemType Directory -Path $managed -Force | Out-Null
    }

    return $paths
  }
}

Describe 'managed-paths parity' -Skip:($IsWindows -eq $false) {

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

    New-ManagedPathLayout | Out-Null

    # ';' not '' — Windows deletes env vars set to empty string,
    # which would fall through to the real registry (see
    # 01-path.Tests.ps1 for the same workaround).
    $env:PATH = ';'
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = ';'
  }

  AfterEach {
    # TestDrive: persists for the whole Pester session, not just this
    # Describe — remove any GitHub.cli_* directory a test created
    # (before $env:LOCALAPPDATA below is restored to its real value)
    # so it cannot leak into a later file's assumptions.
    $packagesRootCleanup = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    Get-ChildItem -LiteralPath $packagesRootCleanup -Directory -Filter 'GitHub.cli_*' -ErrorAction SilentlyContinue |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:PATH = $script:OriginalPath
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
    ${env:ProgramFiles(x86)} = $script:OriginalProgramFilesX86

    Remove-Item Function:\Split-PathEntries -ErrorAction SilentlyContinue
    Remove-Item Function:\Normalize-PathEntry -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-StaticManagedPaths -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-MisePackagesRoot -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-MiseManagedPaths -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetUserPathManifestPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetUserPathDeclaredPackages -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetPackagesRoot -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetUserPathManagedPaths -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-IsManagedPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-RegistryUserPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-RegistryUserPath -ErrorAction SilentlyContinue
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = $null
    $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $null
  }

  It 'computes the identical managed-path set on both surfaces' {
    . $script:ConfDScript
    $confDManagedPaths = @($desiredManagedPaths)

    . $script:RegisterFixture 6>&1 | Out-Null
    $registerManagedPaths = @($desiredManagedPaths)

    $confDManagedPaths | Should -Not -BeNullOrEmpty
    $registerManagedPaths | Should -Be $confDManagedPaths
  }

  It 'computes the identical managed-path set on both surfaces with a winget package declared' {
    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $binDir = Join-Path (Join-Path $packagesRoot 'GitHub.cli_Microsoft.Winget.Source_test') 'bin'
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null

    $manifestPath = 'TestDrive:\winget-manifest.json'
    Set-Content -Path $manifestPath -Value '[{"label":"gh","id":"GitHub.cli","bin":"bin"}]'
    $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $manifestPath

    . $script:ConfDScript
    $confDManagedPaths = @($desiredManagedPaths)

    . $script:RegisterFixture 6>&1 | Out-Null
    $registerManagedPaths = @($desiredManagedPaths)

    $confDManagedPaths | Should -Contain $binDir
    $registerManagedPaths | Should -Be $confDManagedPaths
  }
}
