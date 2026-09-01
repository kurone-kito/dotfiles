# Tests for the Windows Git Bash mandatory-ASLR chezmoi post-apply
# warning script. Exercises: system-wide-not-on no-op (never reading
# the per-image state), already-exempt no-op, exactly-one-warning when
# neither holds, and silent no-op whenever the mitigation query itself
# fails or returns an unreadable shape. Never reads or writes real
# process mitigations -- Get-ProcessMitigation is always Mocked or
# stubbed. Also covers two OS-independent static checks (no Windows
# gate, no mocking): the .chezmoiignore.tmpl registration, and a
# source-text guard that the script never writes a mitigation or checks
# elevation.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot '../../home/run_after_85-warn-git-bash-aslr.ps1'

  # Get-ProcessMitigation ships in a Windows-PowerShell-era binary
  # module; Pester's Mock requires a resolvable command to shadow, so
  # define a harmless stub function when the real cmdlet isn't
  # discoverable on this host, keeping every Mock below a no-op against
  # real state either way. The stub declares the same formal parameters
  # the real cmdlet exposes so Mock -ParameterFilter can bind
  # $Name/$System the same way it would against the real cmdlet.
  #
  # Gated on $IsWindows -ne $false (not a bare truthy check): $IsWindows
  # is $null on Windows PowerShell 5.1 (the variable was added in
  # PowerShell 6), and a bare `if ($IsWindows)` treats that null as
  # falsy, silently skipping this block on the PS5.1 CI leg. On
  # Linux/macOS pwsh, $IsWindows is $false, so this guard also correctly
  # skips stub-definition there -- this file adds a second Describe
  # below (the static checks) that is never skipped, so this BeforeAll
  # runs on every platform, but only ever defines the stub on a Windows
  # host that is missing the real cmdlet.
  $global:DotfilesTestWarnAslrUsedProcessMitigationStub = $false
  if ($IsWindows -ne $false) {
    if (-not (Get-Command Get-ProcessMitigation -ErrorAction SilentlyContinue)) {
      $global:DotfilesTestWarnAslrUsedProcessMitigationStub = $true
      function global:Get-ProcessMitigation {
        param(
          [Parameter()] [string] $Name,
          [switch] $System,
          [switch] $RunningProcesses
        )
      }
    }
  }

  function New-MitigationReport {
    param([Parameter(Mandatory)] [string] $ForceRelocateImages)
    return [pscustomobject]@{ ASLR = [pscustomobject]@{ ForceRelocateImages = $ForceRelocateImages } }
  }
}

Describe '85-warn-git-bash-aslr' -Skip:($IsWindows -eq $false) {

  BeforeEach {
    $script:OriginalSkip = $env:DOTFILES_TEST_WARN_GIT_BASH_ASLR_SKIP_MAIN
    $env:DOTFILES_TEST_WARN_GIT_BASH_ASLR_SKIP_MAIN = '1'
    . $script:Subject
  }

  AfterEach {
    $env:DOTFILES_TEST_WARN_GIT_BASH_ASLR_SKIP_MAIN = $script:OriginalSkip

    foreach ($name in @(
      'Test-DotfilesSystemWideForceRelocateImagesOn'
      'Test-DotfilesGitBashForceRelocateImagesExempt'
      'Invoke-DotfilesWarnGitBashAslr'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  Context 'environment assumptions (no mocks)' {
    It 'Get-ProcessMitigation resolves as a real or stubbed command' {
      # Assumption check, not a mitigation-I/O test: guards against a CI
      # runner where the ProcessMitigations module silently never loads,
      # which would otherwise let every mocked test below pass without
      # ever proving the real cmdlet is reachable.
      Get-Command Get-ProcessMitigation -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty

      # On real Windows, the BeforeAll stub-definer above must not have
      # fired -- otherwise this assertion (and every mocked test below)
      # would pass vacuously against our own stub instead of proving the
      # real ProcessMitigations cmdlet is reachable on this runner.
      if ($IsWindows -ne $false) {
        $global:DotfilesTestWarnAslrUsedProcessMitigationStub | Should -Not -BeTrue
      }
    }
  }

  Context 'system-wide mandatory ASLR not enabled' {
    It 'returns 0, writes no warning, and never reads the per-image mitigation' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'NOTSET' } -ParameterFilter {
        $System -eq $true
      }

      $result = Invoke-DotfilesWarnGitBashAslr -WarningVariable warnings -WarningAction SilentlyContinue

      $result | Should -Be 0
      $warnings | Should -BeNullOrEmpty
      Should -Invoke Get-ProcessMitigation -Times 0 -ParameterFilter { $Name -eq 'bash.exe' }
    }
  }

  Context 'Git Bash already exempt' {
    It 'returns 0 and writes no warning when bash.exe already has the exemption' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' } -ParameterFilter {
        $System -eq $true
      }
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'OFF' } -ParameterFilter {
        $Name -eq 'bash.exe'
      }

      $result = Invoke-DotfilesWarnGitBashAslr -WarningVariable warnings -WarningAction SilentlyContinue

      $result | Should -Be 0
      $warnings | Should -BeNullOrEmpty
    }
  }

  Context 'Git Bash needs the exemption' {
    It 'emits exactly one warning naming repair-git-bash-aslr.ps1 and the elevation requirement, and still returns 0' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' } -ParameterFilter {
        $System -eq $true
      }
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' } -ParameterFilter {
        $Name -eq 'bash.exe'
      }

      $result = Invoke-DotfilesWarnGitBashAslr -WarningVariable warnings -WarningAction SilentlyContinue

      $result | Should -Be 0
      @($warnings).Count | Should -Be 1
      $warnings[0].Message | Should -Match 'repair-git-bash-aslr\.ps1'
      $warnings[0].Message | Should -Match 'elevated'
    }

    It 'still warns when the per-image state is NOTSET rather than ON (anything but OFF is not exempt)' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' } -ParameterFilter {
        $System -eq $true
      }
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'NOTSET' } -ParameterFilter {
        $Name -eq 'bash.exe'
      }

      $result = Invoke-DotfilesWarnGitBashAslr -WarningVariable warnings -WarningAction SilentlyContinue

      $result | Should -Be 0
      @($warnings).Count | Should -Be 1
    }
  }

  Context 'mitigation query fails or is unavailable' {
    It 'returns 0 and writes no warning when the system-wide query throws' {
      Mock Get-ProcessMitigation { throw 'simulated failure' } -ParameterFilter {
        $System -eq $true
      }

      $result = Invoke-DotfilesWarnGitBashAslr -WarningVariable warnings -WarningAction SilentlyContinue

      $result | Should -Be 0
      $warnings | Should -BeNullOrEmpty
      Should -Invoke Get-ProcessMitigation -Times 0 -ParameterFilter { $Name -eq 'bash.exe' }
    }

    It 'returns 0 and writes no warning when the per-image query throws' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' } -ParameterFilter {
        $System -eq $true
      }
      Mock Get-ProcessMitigation { throw 'simulated failure' } -ParameterFilter {
        $Name -eq 'bash.exe'
      }

      $result = Invoke-DotfilesWarnGitBashAslr -WarningVariable warnings -WarningAction SilentlyContinue

      $result | Should -Be 0
      $warnings | Should -BeNullOrEmpty
    }

    It 'returns 0 and writes no warning when the system-wide result has no ASLR property' {
      Mock Get-ProcessMitigation { [pscustomobject]@{} } -ParameterFilter {
        $System -eq $true
      }

      $result = Invoke-DotfilesWarnGitBashAslr -WarningVariable warnings -WarningAction SilentlyContinue

      $result | Should -Be 0
      $warnings | Should -BeNullOrEmpty
    }

    It 'returns 0 and writes no warning when the per-image result has no ASLR property' {
      Mock Get-ProcessMitigation { New-MitigationReport -ForceRelocateImages 'ON' } -ParameterFilter {
        $System -eq $true
      }
      Mock Get-ProcessMitigation { [pscustomobject]@{} } -ParameterFilter {
        $Name -eq 'bash.exe'
      }

      $result = Invoke-DotfilesWarnGitBashAslr -WarningVariable warnings -WarningAction SilentlyContinue

      $result | Should -Be 0
      $warnings | Should -BeNullOrEmpty
    }
  }
}

Describe '85-warn-git-bash-aslr -- static checks (no OS gate, no mocking)' {

  It 'is listed in .chezmoiignore.tmpl''s non-Windows branch' {
    $ignoreFile = Join-Path $PSScriptRoot '../../home/.chezmoiignore.tmpl'
    $lines = Get-Content $ignoreFile

    $lines | Should -Contain '85-warn-git-bash-aslr.ps1'
  }

  It 'never writes a process mitigation and never checks elevation' {
    # A durable regression guard: no functional Mock can prove a call
    # was never made outside the specific scenarios this file happens to
    # test, so this reads the actual source text instead. Checks for the
    # cmdlet/API identifiers themselves, described in prose here (rather
    # than repeated literally) so the script's own header comments never
    # trip this guard by naming what it deliberately avoids.
    $source = Get-Content -Path $script:Subject -Raw

    $source | Should -Not -Match 'Set-ProcessMitigation'
    $source | Should -Not -Match 'WindowsBuiltInRole'
    $source | Should -Not -Match 'WindowsPrincipal'
  }
}
