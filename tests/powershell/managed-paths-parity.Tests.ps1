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
    $paths.MiseShims = Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'shims'

    foreach ($managed in @(
      $paths.WinGetLinks
      $paths.Zellij
      $paths.GnuWin32
      $paths.HomeLocalBin
      $paths.HomeCargoBin
      $paths.CurrentMiseBin
      $paths.MiseShims
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
    # Captured immediately (before $env:LOCALAPPDATA is reassigned)
    # so the AfterEach cleanup below always targets this
    # TestDrive-rooted path, even if a later step in this block
    # were to fail — never the real %LOCALAPPDATA%, which could
    # otherwise be deleted from.
    $script:TestWingetPackagesRoot = Join-Path $localAppDataRoot 'Microsoft\WinGet\Packages'

    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force
    $env:LOCALAPPDATA = $localAppDataRoot
    ${env:ProgramFiles(x86)} = $programFilesX86Root

    New-ManagedPathLayout | Out-Null

    # jdx.mise is now a plain declared package (a repo-shipped
    # default, see docs/winget-user-path.md), not a hardcoded special
    # case — declare it here so both surfaces still find a non-empty
    # managed set through the generic mechanism.
    $script:BaseWingetManifestPath = 'TestDrive:\winget-manifest-base.json'
    Set-Content -Path $script:BaseWingetManifestPath -Value '[{"label":"mise","id":"jdx.mise","bin":"mise/bin"}]'
    $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $script:BaseWingetManifestPath

    # ';' not '' — Windows deletes env vars set to empty string,
    # which would fall through to the real registry (see
    # 01-path.Tests.ps1 for the same workaround).
    $env:PATH = ';'
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = ';'
  }

  AfterEach {
    # TestDrive: persists for the whole Pester session, not just this
    # Describe — remove any GitHub.cli_*/twpayne.chezmoi_* directory a
    # test created (before $env:LOCALAPPDATA below is restored to its
    # real value) so it cannot leak into a later file's assumptions.
    # Uses the TestDrive-rooted path captured in BeforeEach rather than
    # re-reading $env:LOCALAPPDATA, so a partially-failed BeforeEach
    # can never point this cleanup at a real %LOCALAPPDATA%.
    if (-not [string]::IsNullOrEmpty($script:TestWingetPackagesRoot)) {
      foreach ($filter in @('GitHub.cli_*', 'twpayne.chezmoi_*', 'Gyan.FFmpeg_*')) {
        Get-ChildItem -LiteralPath $script:TestWingetPackagesRoot -Directory -Filter $filter -ErrorAction SilentlyContinue |
          Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      }
    }

    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    $env:PATH = $script:OriginalPath
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
    ${env:ProgramFiles(x86)} = $script:OriginalProgramFilesX86

    Remove-Item Function:\Split-PathEntries -ErrorAction SilentlyContinue
    Remove-Item Function:\Normalize-PathEntry -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-StaticManagedPaths -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetUserPathManifestPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetUserPathDeclaredPackages -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetPackagesRoot -ErrorAction SilentlyContinue
    Remove-Item Function:\Resolve-WingetUserPathBinDirectory -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetUserPathManagedPaths -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-IsManagedPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-RegistryUserPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-RegistryUserPath -ErrorAction SilentlyContinue
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = $null
    $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $null
    $script:TestWingetPackagesRoot = $null
    $script:BaseWingetManifestPath = $null
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

  It 'computes the identical managed-path set on both surfaces with the twpayne.chezmoi default declared' {
    # chezmoi.exe sits directly in its package directory (no bin
    # subpath — see the shipped default's empty "bin" below).
    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $chezmoiDir = Join-Path $packagesRoot 'twpayne.chezmoi_Microsoft.Winget.Source_test'
    New-Item -ItemType Directory -Path $chezmoiDir -Force | Out-Null

    # Literal output of `chezmoi execute-template` against
    # winget-user-path-packages.json.tmpl with no user declarations —
    # kept identical to the assertion in
    # winget-user-path-packages-tmpl.Tests.ps1's "produces the exact
    # deterministic JSON..." case, so this exercises the actual
    # rendered-manifest shape (both shipped defaults) rather than an
    # independently hand-written fixture. Keep both in sync.
    $manifestPath = 'TestDrive:\winget-manifest-chezmoi.json'
    Set-Content -Path $manifestPath -Value (
      '[{"bin":"","enabled":true,"id":"twpayne.chezmoi","label":"chezmoi"},' +
      '{"bin":"ffmpeg-*-full_build/bin","enabled":true,"id":"Gyan.FFmpeg","label":"ffmpeg"},' +
      '{"bin":"mise/bin","enabled":true,"id":"jdx.mise","label":"mise"},' +
      '{"bin":"","enabled":true,"id":"Ngrok.Ngrok","label":"ngrok"},' +
      '{"bin":"","enabled":true,"id":"SQLite.SQLite","label":"sqlite"}]'
    )
    $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $manifestPath

    . $script:ConfDScript
    $confDManagedPaths = @($desiredManagedPaths)

    . $script:RegisterFixture 6>&1 | Out-Null
    $registerManagedPaths = @($desiredManagedPaths)

    $confDManagedPaths | Should -Contain $chezmoiDir
    $registerManagedPaths | Should -Be $confDManagedPaths
  }

  It 'computes the identical managed-path set on both surfaces with a wildcard bin (ffmpeg-style versioned directory)' {
    # Materializes a real versioned package directory on disk (not
    # just a JSON-literal update) so this parity gate actually
    # exercises Resolve-WingetUserPathBinDirectory's wildcard path on
    # both surfaces, rather than staying green because an unmatched
    # wildcard segment would let both surfaces silently contribute
    # nothing.
    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $ffmpegDir = Join-Path (Join-Path $packagesRoot 'Gyan.FFmpeg_Microsoft.Winget.Source_test') 'ffmpeg-9.0-full_build\bin'
    New-Item -ItemType Directory -Path $ffmpegDir -Force | Out-Null

    $manifestPath = 'TestDrive:\winget-manifest-ffmpeg.json'
    Set-Content -Path $manifestPath -Value '[{"label":"ffmpeg","id":"Gyan.FFmpeg","bin":"ffmpeg-*-full_build/bin"}]'
    $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $manifestPath

    . $script:ConfDScript
    $confDManagedPaths = @($desiredManagedPaths)

    . $script:RegisterFixture 6>&1 | Out-Null
    $registerManagedPaths = @($desiredManagedPaths)

    $confDManagedPaths | Should -Contain $ffmpegDir
    $registerManagedPaths | Should -Be $confDManagedPaths
  }
}
