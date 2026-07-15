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
    $paths.HomeCargoBin = Join-Path $HOME '.cargo\bin'
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
      $paths.HomeCargoBin
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
    # Captured immediately (before $env:LOCALAPPDATA is reassigned)
    # so the "winget declared packages" Context's AfterEach cleanup
    # always targets this TestDrive-rooted path, even if a later
    # step in this block were to fail — never the real
    # %LOCALAPPDATA%, which could otherwise be deleted from.
    $script:TestWingetPackagesRoot = Join-Path $localAppDataRoot 'Microsoft\WinGet\Packages'

    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force
    $env:LOCALAPPDATA = $localAppDataRoot
    ${env:ProgramFiles(x86)} = $programFilesX86Root

    $script:Paths = New-ManagedPathLayout

    # jdx.mise is now a plain declared package (a repo-shipped
    # default, see docs/winget-user-path.md), not a hardcoded special
    # case — declare it here so the existing mise PATH scenarios below
    # keep exercising it through the generic mechanism. The "winget
    # declared packages" Context overrides this with its own manifest.
    $script:BaseWingetManifestPath = 'TestDrive:\winget-manifest-base.json'
    Set-Content -Path $script:BaseWingetManifestPath -Value '[{"label":"mise","id":"jdx.mise","bin":"mise/bin"}]'
    $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $script:BaseWingetManifestPath

    # Disable registry sync by default so existing tests are not
    # affected by the real Windows User PATH.
    # Use ';' not '' — Windows deletes env vars set to empty string,
    # which would cause Get-RegistryUserPath to fall through to the
    # real registry.  A single ';' is non-null yet splits to only
    # empty entries that the $norm -ne '' guard skips.
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = ';'

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
    Remove-Item Function:\Get-WingetUserPathManifestPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetUserPathDeclaredPackages -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetPackagesRoot -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-WingetUserPathManagedPaths -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-IsManagedPath -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-RegistryUserPath -ErrorAction SilentlyContinue
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = $null
    $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $null
    $script:TestWingetPackagesRoot = $null
    $script:BaseWingetManifestPath = $null
  }

  It 'reconciles managed entries and removes stale winget package paths' {
    . $script:Subject

    $env:PATH | Should -Be (@(
      $script:Paths.CurrentMiseBin
      $script:Paths.WinGetLinks
      $script:Paths.Zellij
      $script:Paths.GnuWin32
      $script:Paths.HomeLocalBin
      $script:Paths.HomeCargoBin
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

  It 'lists the default Cargo bin among the static managed paths' {
    . $script:Subject

    $static = @(Get-StaticManagedPaths)
    $static | Should -Contain (Join-Path $HOME '.cargo\bin')
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

  Context 'winget declared packages' {

    BeforeEach {
      $script:WingetManifestPath = 'TestDrive:\winget-manifest.json'
      $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST = $script:WingetManifestPath
    }

    AfterEach {
      # TestDrive: persists across It blocks within this run, so any
      # GitHub.cli_* directory a test creates must be removed here —
      # otherwise it leaks into later tests (e.g. "contributes
      # nothing") that assert no matching directory exists on disk.
      # Uses the TestDrive-rooted path captured in the outer
      # BeforeEach rather than re-reading $env:LOCALAPPDATA, so a
      # partially-failed BeforeEach can never point this cleanup at
      # a real %LOCALAPPDATA%.
      if (-not [string]::IsNullOrEmpty($script:TestWingetPackagesRoot)) {
        Get-ChildItem -LiteralPath $script:TestWingetPackagesRoot -Directory -Filter 'GitHub.cli_*' -ErrorAction SilentlyContinue |
          Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      }
    }

    It 'adds a declared package real bin directory ahead of WinGet\Links' {
      $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
      $binDir = Join-Path (Join-Path $packagesRoot 'GitHub.cli_Microsoft.Winget.Source_test') 'bin'
      New-Item -ItemType Directory -Path $binDir -Force | Out-Null

      Set-Content -Path $script:WingetManifestPath -Value '[{"label":"gh","id":"GitHub.cli","bin":"bin"}]'

      . $script:Subject

      $entries = @($env:PATH -split ';')
      $entries | Should -Contain $binDir
      ([array]::IndexOf($entries, $binDir)) |
        Should -BeLessThan ([array]::IndexOf($entries, $script:Paths.WinGetLinks))
    }

    It 'removes a stale sibling directory of a declared package while keeping the current one' {
      $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
      $currentBinDir = Join-Path (Join-Path $packagesRoot 'GitHub.cli_Microsoft.Winget.Source_test') 'bin'
      $staleBinDir = Join-Path (Join-Path $packagesRoot 'GitHub.cli_Microsoft.Winget.Source_stale') 'bin'
      New-Item -ItemType Directory -Path $currentBinDir -Force | Out-Null

      Set-Content -Path $script:WingetManifestPath -Value '[{"label":"gh","id":"GitHub.cli","bin":"bin"}]'

      $env:PATH = @(
        $script:Paths.UnrelatedA
        $staleBinDir
        $script:Paths.WinGetLinks
      ) -join ';'

      . $script:Subject

      $entries = @($env:PATH -split ';')
      $entries | Should -Contain $currentBinDir
      $entries | Should -Not -Contain $staleBinDir
    }

    It 'removes a previously-added directory once its declared package''s bin changes' {
      $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
      $oldBinDir = Join-Path (Join-Path $packagesRoot 'GitHub.cli_Microsoft.Winget.Source_test') 'old-bin'
      $newBinDir = Join-Path (Join-Path $packagesRoot 'GitHub.cli_Microsoft.Winget.Source_test') 'new-bin'
      New-Item -ItemType Directory -Path $oldBinDir -Force | Out-Null
      New-Item -ItemType Directory -Path $newBinDir -Force | Out-Null

      $env:PATH = @(
        $script:Paths.UnrelatedA
        $oldBinDir
        $script:Paths.WinGetLinks
      ) -join ';'

      Set-Content -Path $script:WingetManifestPath -Value (
        '[{"label":"gh","id":"GitHub.cli","bin":"new-bin"}]'
      )

      . $script:Subject

      $entries = @($env:PATH -split ';')
      $entries | Should -Not -Contain $oldBinDir
      $entries | Should -Contain $newBinDir
    }

    It 'removes a previously-added directory once its declared package is disabled' {
      $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
      $binDir = Join-Path (Join-Path $packagesRoot 'GitHub.cli_Microsoft.Winget.Source_test') 'bin'
      New-Item -ItemType Directory -Path $binDir -Force | Out-Null

      $env:PATH = @(
        $script:Paths.UnrelatedA
        $binDir
        $script:Paths.WinGetLinks
      ) -join ';'

      Set-Content -Path $script:WingetManifestPath -Value (
        '[{"label":"gh","id":"GitHub.cli","bin":"bin","enabled":false}]'
      )

      . $script:Subject

      $entries = @($env:PATH -split ';')
      $entries | Should -Not -Contain $binDir
      $entries | Should -Contain $script:Paths.UnrelatedA
    }

    It 'contributes nothing when the declared package has no matching directory on disk' {
      # This Context's manifest declares only "gh" (overriding the
      # outer BeforeEach's mise-declaring manifest), so mise
      # contributes nothing here either.
      Set-Content -Path $script:WingetManifestPath -Value '[{"label":"gh","id":"GitHub.cli","bin":"bin"}]'

      . $script:Subject

      $env:PATH | Should -Be (@(
        $script:Paths.WinGetLinks
        $script:Paths.Zellij
        $script:Paths.GnuWin32
        $script:Paths.HomeLocalBin
        $script:Paths.HomeCargoBin
        $script:Paths.UnrelatedA
        $script:Paths.UnrelatedB
      ) -join ';')
    }

    It 'is a no-op when no packages are declared (empty manifest)' {
      Set-Content -Path $script:WingetManifestPath -Value '[]'

      . $script:Subject

      $env:PATH | Should -Be (@(
        $script:Paths.WinGetLinks
        $script:Paths.Zellij
        $script:Paths.GnuWin32
        $script:Paths.HomeLocalBin
        $script:Paths.HomeCargoBin
        $script:Paths.UnrelatedA
        $script:Paths.UnrelatedB
      ) -join ';')
    }
  }
}
