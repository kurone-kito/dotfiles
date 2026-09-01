# Tests for the Git Bash mandatory-ASLR repair helper.
# Exercises: admin elevation gate, system-wide ForceRelocateImages
# no-op, dynamic Git for Windows root resolution (registry + PATH
# fallback), per-image idempotency, and the usr\bin-only /
# never-system-scope mitigation write guarantees. Never reads or
# writes real process mitigations or the real registry -- everything
# goes through Mock or a TestDrive-rooted fake install layout.

BeforeAll {
  $script:Subject = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home') 'dot_local') 'bin') 'executable_repair-git-bash-aslr.ps1'

  # Get-ProcessMitigation / Set-ProcessMitigation ship in a
  # Windows-PowerShell-era binary module; Pester's Mock requires a
  # resolvable command to shadow, so define harmless stub functions
  # when the real cmdlets aren't discoverable on this host, keeping
  # every Mock below a no-op against real state either way. The stubs
  # declare the same formal parameters the real cmdlets expose so that
  # Mock -ParameterFilter can bind $Name/$System/$Disable the same way
  # it would against the real, richer cmdlet.
  #
  # Gated on $IsWindows -ne $false (not a bare truthy check): $IsWindows
  # is $null on Windows PowerShell 5.1 (the variable was added in
  # PowerShell 6), and a bare `if ($IsWindows)` treats that null as
  # falsy, silently skipping this whole block -- and with it the
  # native-cmdlet-resolvable check -- on the PS5.1 CI leg. This Describe
  # already skips entirely on non-Windows via the same null-safe
  # `-Skip:($IsWindows -eq $false)` idiom, so a file-level BeforeAll
  # here never actually executes for a Linux/macOS Pester run (verified
  # empirically against Pester 5.6.1 and 6.0.1, single-file and
  # whole-directory invocations, with and without -CI: a skipped
  # Describe's sibling BeforeAll never runs). The explicit guard is
  # defense in depth against any future Pester behavior change, and
  # keeps global: stubs from ever being defined outside the platforms
  # that need them.
  $global:DotfilesTestUsedProcessMitigationStub = $false
  if ($IsWindows -ne $false) {
    if (-not (Get-Command Get-ProcessMitigation -ErrorAction SilentlyContinue)) {
      $global:DotfilesTestUsedProcessMitigationStub = $true
      function global:Get-ProcessMitigation {
        param(
          [Parameter()] [string] $Name,
          [switch] $System,
          [switch] $RunningProcesses
        )
      }
    }
    if (-not (Get-Command Set-ProcessMitigation -ErrorAction SilentlyContinue)) {
      $global:DotfilesTestUsedProcessMitigationStub = $true
      function global:Set-ProcessMitigation {
        param(
          [Parameter()] [string] $Name,
          [string[]] $Disable,
          [string[]] $Enable,
          [switch] $System
        )
      }
    }
  }

  function New-FakeGitForWindowsLayout {
    param(
      [Parameter(Mandatory)] [string] $Root,
      [string[]] $UsrBinNames = @('bash.exe', 'sh.exe'),
      [string[]] $Mingw64BinNames = @('git.exe')
    )

    $usrBin = Join-Path $Root 'usr\bin'
    $mingw64Bin = Join-Path $Root 'mingw64\bin'
    New-Item -ItemType Directory -Path $usrBin -Force | Out-Null
    New-Item -ItemType Directory -Path $mingw64Bin -Force | Out-Null

    foreach ($name in $UsrBinNames) {
      New-Item -ItemType File -Path (Join-Path $usrBin $name) -Force | Out-Null
    }
    foreach ($name in $Mingw64BinNames) {
      New-Item -ItemType File -Path (Join-Path $mingw64Bin $name) -Force | Out-Null
    }

    return [pscustomobject]@{
      Root       = $Root
      UsrBin     = $usrBin
      Mingw64Bin = $mingw64Bin
    }
  }

  function New-MitigationReport {
    param([Parameter(Mandatory)] [string] $ForceRelocateImages)
    return [pscustomobject]@{ ASLR = [pscustomobject]@{ ForceRelocateImages = $ForceRelocateImages } }
  }
}

Describe 'repair-git-bash-aslr' -Skip:($IsWindows -eq $false) {

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_REPAIR_GIT_BASH_ASLR_SKIP_MAIN
    $env:DOTFILES_TEST_REPAIR_GIT_BASH_ASLR_SKIP_MAIN = '1'
    . $script:Subject
  }

  AfterEach {
    $env:DOTFILES_TEST_REPAIR_GIT_BASH_ASLR_SKIP_MAIN = $script:OriginalSkip

    foreach ($name in @(
      'Test-DotfilesAdminElevation'
      'Write-DotfilesFatalError'
      'Test-DotfilesSystemWideForceRelocateImagesEnabled'
      'Resolve-DotfilesGitForWindowsRoot'
      'Get-DotfilesGitBashUsrBinExecutables'
      'Test-DotfilesImageForceRelocateImagesDisabled'
      'Disable-DotfilesImageForceRelocateImages'
      'Invoke-DotfilesRepairGitBashAslr'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  Context 'environment assumptions (no mocks)' {
    It 'Get-ProcessMitigation resolves as a real or stubbed command' {
      # Assumption check, not a mitigation-I/O test: guards against a
      # CI runner where the ProcessMitigations module silently never
      # loads, which would otherwise let every mocked test below pass
      # without ever proving the real cmdlets are reachable.
      Get-Command Get-ProcessMitigation -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty

      # On real Windows, the BeforeAll stub-definer above must not have
      # fired -- otherwise this assertion (and every mocked test below)
      # would pass vacuously against our own stub instead of proving the
      # real ProcessMitigations cmdlets are reachable on this runner.
      # Null-safe check (see the BeforeAll comment above): a bare
      # `if ($IsWindows)` is falsy on PS5.1, which would silently skip
      # this assertion on that CI leg instead of enforcing it.
      if ($IsWindows -ne $false) {
        $global:DotfilesTestUsedProcessMitigationStub | Should -Not -BeTrue
      }
    }

    It 'Test-DotfilesAdminElevation returns false for non-elevated session' -Skip:(
      [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT -and
      ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    ) {
      Test-DotfilesAdminElevation | Should -BeFalse
    }
  }

  Context 'Invoke-DotfilesRepairGitBashAslr -- elevation gate' {
    It 'returns 1 and writes a fatal error naming elevation, without any mitigation read or write' {
      Mock Test-DotfilesAdminElevation { $false }
      Mock Test-DotfilesSystemWideForceRelocateImagesEnabled { }
      Mock Get-ProcessMitigation { }
      Mock Set-ProcessMitigation { }
      Mock Write-DotfilesFatalError { }

      $result = Invoke-DotfilesRepairGitBashAslr

      $result | Should -Be 1
      Should -Invoke Write-DotfilesFatalError -Times 1 -ParameterFilter {
        $Message -match 'administrator elevation'
      }
      Should -Invoke Test-DotfilesSystemWideForceRelocateImagesEnabled -Times 0
      Should -Invoke Set-ProcessMitigation -Times 0
    }
  }

  Context 'Invoke-DotfilesRepairGitBashAslr -- system-wide mitigation not enabled' {
    It 'returns 0, prints an explanatory no-op message, and never touches per-image mitigations' {
      Mock Test-DotfilesAdminElevation { $true }
      Mock Test-DotfilesSystemWideForceRelocateImagesEnabled { $false }
      Mock Resolve-DotfilesGitForWindowsRoot { }
      Mock Get-ProcessMitigation { }
      Mock Set-ProcessMitigation { }

      $result = Invoke-DotfilesRepairGitBashAslr

      $result | Should -Be 0
      Should -Invoke Resolve-DotfilesGitForWindowsRoot -Times 0
      Should -Invoke Set-ProcessMitigation -Times 0
    }
  }

  Context 'Invoke-DotfilesRepairGitBashAslr -- git root unresolvable' {
    It 'returns 1 with guidance and performs no mitigation write' {
      Mock Test-DotfilesAdminElevation { $true }
      Mock Test-DotfilesSystemWideForceRelocateImagesEnabled { $true }
      Mock Resolve-DotfilesGitForWindowsRoot { $null }
      Mock Write-DotfilesFatalError { }
      Mock Set-ProcessMitigation { }

      $result = Invoke-DotfilesRepairGitBashAslr

      $result | Should -Be 1
      Should -Invoke Write-DotfilesFatalError -Times 1 -ParameterFilter {
        # Must name every hive Resolve-DotfilesGitForWindowsRoot actually
        # checks (including HKCU, added for the per-user install case) --
        # guards against the guidance text silently drifting out of sync
        # with the real candidate list again.
        $Message -match 'Git for Windows install root' -and
        $Message -match 'HKCU:\\SOFTWARE\\GitForWindows'
      }
      Should -Invoke Set-ProcessMitigation -Times 0
    }
  }

  Context 'Invoke-DotfilesRepairGitBashAslr -- empty usr\bin' {
    It 'returns 1 when the resolved install has no *.exe under usr\bin' {
      $layoutRoot = Join-Path 'TestDrive:\' 'empty-git'
      New-Item -ItemType Directory -Path (Join-Path $layoutRoot 'usr\bin') -Force | Out-Null

      Mock Test-DotfilesAdminElevation { $true }
      Mock Test-DotfilesSystemWideForceRelocateImagesEnabled { $true }
      Mock Resolve-DotfilesGitForWindowsRoot { $layoutRoot }
      Mock Write-DotfilesFatalError { }
      Mock Set-ProcessMitigation { }

      $result = Invoke-DotfilesRepairGitBashAslr

      $result | Should -Be 1
      Should -Invoke Write-DotfilesFatalError -Times 1 -ParameterFilter {
        $Message -match 'looks incomplete'
      }
      Should -Invoke Set-ProcessMitigation -Times 0
    }
  }

  Context 'Invoke-DotfilesRepairGitBashAslr -- already-exempted host (idempotency)' {
    It 'returns 0, reports nothing to change, and never calls Set-ProcessMitigation' {
      $layout = New-FakeGitForWindowsLayout -Root (Join-Path 'TestDrive:\' 'already-exempt')

      Mock Test-DotfilesAdminElevation { $true }
      Mock Test-DotfilesSystemWideForceRelocateImagesEnabled { $true }
      Mock Resolve-DotfilesGitForWindowsRoot { $layout.Root }
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'OFF' } -ParameterFilter {
        $Name -in @('bash.exe', 'sh.exe')
      }
      Mock Set-ProcessMitigation { }

      $result = Invoke-DotfilesRepairGitBashAslr

      $result | Should -Be 0
      Should -Invoke Set-ProcessMitigation -Times 0
    }
  }

  Context 'Invoke-DotfilesRepairGitBashAslr -- mixed host needing repair' {
    It 'disables ForceRelocateImages only for images that are not already OFF' {
      $layout = New-FakeGitForWindowsLayout -Root (Join-Path 'TestDrive:\' 'mixed') `
        -UsrBinNames @('bash.exe', 'sh.exe', 'perl.exe')

      Mock Test-DotfilesAdminElevation { $true }
      Mock Test-DotfilesSystemWideForceRelocateImagesEnabled { $true }
      Mock Resolve-DotfilesGitForWindowsRoot { $layout.Root }
      Mock Get-ProcessMitigation {
        New-MitigationReport -ForceRelocateImages 'OFF'
      } -ParameterFilter { $Name -eq 'perl.exe' }
      Mock Get-ProcessMitigation {
        New-MitigationReport -ForceRelocateImages 'ON'
      } -ParameterFilter { $Name -in @('bash.exe', 'sh.exe') }
      Mock Set-ProcessMitigation { }

      $result = Invoke-DotfilesRepairGitBashAslr

      $result | Should -Be 0
      Should -Invoke Set-ProcessMitigation -Times 2
      Should -Invoke Set-ProcessMitigation -Times 1 -ParameterFilter {
        $Name -eq 'bash.exe' -and $Disable -eq 'ForceRelocateImages'
      }
      Should -Invoke Set-ProcessMitigation -Times 1 -ParameterFilter {
        $Name -eq 'sh.exe' -and $Disable -eq 'ForceRelocateImages'
      }
      Should -Invoke Set-ProcessMitigation -Times 0 -ParameterFilter {
        $Name -eq 'perl.exe'
      }
    }
  }

  Context 'Invoke-DotfilesRepairGitBashAslr -- scope guards' {
    It 'never targets mingw64\bin and never writes a system-scope mitigation' {
      $layout = New-FakeGitForWindowsLayout -Root (Join-Path 'TestDrive:\' 'scope-guard') `
        -UsrBinNames @('bash.exe') -Mingw64BinNames @('git.exe')

      Mock Test-DotfilesAdminElevation { $true }
      Mock Test-DotfilesSystemWideForceRelocateImagesEnabled { $true }
      Mock Resolve-DotfilesGitForWindowsRoot { $layout.Root }
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' }
      Mock Set-ProcessMitigation { }

      $result = Invoke-DotfilesRepairGitBashAslr

      $result | Should -Be 0
      Should -Invoke Set-ProcessMitigation -Times 1
      Should -Invoke Set-ProcessMitigation -Times 0 -ParameterFilter { $Name -eq 'git.exe' }
      Should -Invoke Set-ProcessMitigation -Times 0 -ParameterFilter { $System -eq $true }
    }
  }

  Context 'Resolve-DotfilesGitForWindowsRoot' {
    # A Mock with -ParameterFilter intercepts every call to that command
    # within scope; a call that matches no registered filter (and has no
    # unconditional fallback) is a hard Pester error -- it does NOT fall
    # through to the real cmdlet, and re-invoking the real, module-qualified
    # cmdlet from inside a Mock body recurses back into the same mock
    # instead of the original implementation. So every Test-Path /
    # Get-Command / Get-ItemProperty mock below enumerates every literal
    # path or name the SUT can possibly query in that scenario and returns
    # a canned value for each, with no fallback branch.
    It 'resolves via the GitForWindows registry key when usr\bin exists there' {
      $layout = New-FakeGitForWindowsLayout -Root (Join-Path 'TestDrive:\' 'registry-hit')
      $usrBinPath = $layout.UsrBin

      Mock Test-Path {
        if ($LiteralPath -eq 'HKLM:\SOFTWARE\GitForWindows') {
          return $true
        }
        return $LiteralPath -eq $usrBinPath
      }
      Mock Get-ItemProperty {
        if ($LiteralPath -eq 'HKLM:\SOFTWARE\GitForWindows') {
          return [pscustomobject]@{ InstallPath = $layout.Root }
        }
        return $null
      }

      Resolve-DotfilesGitForWindowsRoot | Should -Be $layout.Root
    }

    It 'resolves via the per-user HKCU registry key when HKLM keys are absent (non-admin install)' {
      # A "only for me" (non-admin) Git for Windows install writes
      # Software\GitForWindows under HKCU instead of HKLM -- same
      # subkey and value name, different hive (git-for-windows/git#455).
      $layout = New-FakeGitForWindowsLayout -Root (Join-Path 'TestDrive:\' 'hkcu-hit')
      $usrBinPath = $layout.UsrBin

      Mock Test-Path {
        if ($LiteralPath -in @(
            'HKLM:\SOFTWARE\GitForWindows'
            'HKLM:\SOFTWARE\WOW6432Node\GitForWindows'
          )) {
          return $false
        }
        if ($LiteralPath -eq 'HKCU:\SOFTWARE\GitForWindows') {
          return $true
        }
        return $LiteralPath -eq $usrBinPath
      }
      Mock Get-ItemProperty {
        if ($LiteralPath -eq 'HKCU:\SOFTWARE\GitForWindows') {
          return [pscustomobject]@{ InstallPath = $layout.Root }
        }
        return $null
      }

      Resolve-DotfilesGitForWindowsRoot | Should -Be $layout.Root
    }

    It 'falls back to git.exe on PATH under cmd\git.exe when the registry keys are absent' {
      $layout = New-FakeGitForWindowsLayout -Root (Join-Path 'TestDrive:\' 'path-fallback-cmd')
      $cmdDir = Join-Path $layout.Root 'cmd'
      $gitExe = Join-Path $cmdDir 'git.exe'
      New-Item -ItemType Directory -Path $cmdDir -Force | Out-Null
      New-Item -ItemType File -Path $gitExe -Force | Out-Null
      $usrBinPath = $layout.UsrBin

      Mock Test-Path {
        if ($LiteralPath -in @(
            'HKLM:\SOFTWARE\GitForWindows'
            'HKLM:\SOFTWARE\WOW6432Node\GitForWindows'
            'HKCU:\SOFTWARE\GitForWindows'
          )) {
          return $false
        }
        return $LiteralPath -eq $usrBinPath
      }
      Mock Get-Command {
        if ($Name -eq 'git.exe') {
          return [pscustomobject]@{ Source = $gitExe }
        }
        return $null
      }

      Resolve-DotfilesGitForWindowsRoot | Should -Be $layout.Root
    }

    It 'falls back to git.exe on PATH under mingw64\bin\git.exe when the registry keys are absent' {
      $layout = New-FakeGitForWindowsLayout -Root (Join-Path 'TestDrive:\' 'path-fallback-mingw64')
      $gitExe = Join-Path $layout.Mingw64Bin 'git.exe'
      New-Item -ItemType File -Path $gitExe -Force | Out-Null
      $usrBinPath = $layout.UsrBin

      Mock Test-Path {
        if ($LiteralPath -in @(
            'HKLM:\SOFTWARE\GitForWindows'
            'HKLM:\SOFTWARE\WOW6432Node\GitForWindows'
            'HKCU:\SOFTWARE\GitForWindows'
          )) {
          return $false
        }
        return $LiteralPath -eq $usrBinPath
      }
      Mock Get-Command {
        if ($Name -eq 'git.exe') {
          return [pscustomobject]@{ Source = $gitExe }
        }
        return $null
      }

      Resolve-DotfilesGitForWindowsRoot | Should -Be $layout.Root
    }

    It 'falls back to git.exe on PATH under usr\bin\git.exe when the registry keys are absent' {
      $layout = New-FakeGitForWindowsLayout -Root (Join-Path 'TestDrive:\' 'path-fallback-usrbin')
      $gitExe = Join-Path $layout.UsrBin 'git.exe'
      New-Item -ItemType File -Path $gitExe -Force | Out-Null
      $usrBinPath = $layout.UsrBin

      Mock Test-Path {
        if ($LiteralPath -in @(
            'HKLM:\SOFTWARE\GitForWindows'
            'HKLM:\SOFTWARE\WOW6432Node\GitForWindows'
            'HKCU:\SOFTWARE\GitForWindows'
          )) {
          return $false
        }
        return $LiteralPath -eq $usrBinPath
      }
      Mock Get-Command {
        if ($Name -eq 'git.exe') {
          return [pscustomobject]@{ Source = $gitExe }
        }
        return $null
      }

      Resolve-DotfilesGitForWindowsRoot | Should -Be $layout.Root
    }

    It 'returns $null when neither the registry nor git.exe on PATH resolve' {
      Mock Test-Path {
        if ($LiteralPath -in @(
            'HKLM:\SOFTWARE\GitForWindows'
            'HKLM:\SOFTWARE\WOW6432Node\GitForWindows'
            'HKCU:\SOFTWARE\GitForWindows'
          )) {
          return $false
        }
        return $false
      }
      Mock Get-Command {
        if ($Name -eq 'git.exe') {
          return $null
        }
        return $null
      }

      Resolve-DotfilesGitForWindowsRoot | Should -BeNullOrEmpty
    }
  }

  Context 'Test-DotfilesImageForceRelocateImagesDisabled' {
    It 'returns true when the image already reports OFF' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'OFF' }

      Test-DotfilesImageForceRelocateImagesDisabled -ImageName 'bash.exe' | Should -BeTrue
    }

    It 'returns false when the image reports ON' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' }

      Test-DotfilesImageForceRelocateImagesDisabled -ImageName 'bash.exe' | Should -BeFalse
    }
  }

  Context 'Test-DotfilesSystemWideForceRelocateImagesEnabled' {
    It 'returns true when the system-wide policy is ON' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' } -ParameterFilter {
        $System -eq $true
      }

      Test-DotfilesSystemWideForceRelocateImagesEnabled | Should -BeTrue
    }

    It 'returns false when the system-wide policy is NOTSET/OFF' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'NOTSET' } -ParameterFilter {
        $System -eq $true
      }

      Test-DotfilesSystemWideForceRelocateImagesEnabled | Should -BeFalse
    }
  }
}
