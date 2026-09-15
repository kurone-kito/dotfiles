# Tests for the home/dot_config/idd-skill/config.json.tmpl chezmoi
# template's Windows-branch rendering: the critiqueLoop.delegate and
# critiqueLoop.telemetryHook pwsh-vs-powershell.exe fallback command
# construction. Renders the real template via `chezmoi execute-template`
# (mirrors sshd-config-tmpl.Tests.ps1 / winget-user-path-packages-tmpl.Tests.ps1)
# so this OS-conditional branch gets real rendering coverage instead of
# only code-inspection review. The POSIX-branch quoting and single-token
# behavior are already covered by tests/bash/idd-skill-config-tmpl.bats;
# this file covers only what that one cannot: the Windows branch, on both
# hosts.
#
# Skipped entirely when chezmoi is not available on PATH (e.g., minimal
# Windows runners).
#
# Windows-runner behavior for the "powershell.exe fallback" context is
# unverified at authoring time (written and run only from WSL/Linux): the
# "pwsh available" context above is the load-bearing one on an actual
# Windows CI leg. The fallback context copies `(Get-Command
# chezmoi).Source` into an isolated directory; if the Windows runner
# resolves `chezmoi` through a package-manager shim (e.g. scoop/winget)
# rather than the real binary, that copy may not behave identically. If
# this context fails only on a Windows CI leg after this lands, treat it
# as an ordinary test failure to fix, not a reason to skip or remove the
# context.

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
  $script:HasPwsh = [bool] (Get-Command pwsh -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoHome = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home' | Resolve-Path
  $script:TemplatePath = Join-Path (Join-Path $script:RepoHome 'dot_config') (Join-Path 'idd-skill' 'config.json.tmpl')
  $script:ChezmoiSource = (Get-Command chezmoi -ErrorAction SilentlyContinue).Source

  function Invoke-Render {
    param(
      [string] $Os,
      [string] $ChezmoiPath = $script:ChezmoiSource,
      [string] $PathOverride
    )
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("idd-skill-config-dest-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    # --override-data-file rather than the inline --override-data string:
    # Windows PowerShell 5.1's native-command argument passing mangles
    # embedded double-quotes in a `{"chezmoi":{"os":"..."}}` style
    # argument, unlike PowerShell 7+ (mirrors sshd-config-tmpl.Tests.ps1's
    # Invoke-Render). The file needs a .json extension -- chezmoi rejects
    # an extensionless override-data file with "unknown format".
    $overrideDataFile = Join-Path ([IO.Path]::GetTempPath()) ("idd-skill-config-override-{0}.json" -f [guid]::NewGuid())
    $overrideJson = "{`"chezmoi`":{`"os`":`"$Os`"}}"
    [System.IO.File]::WriteAllText($overrideDataFile, $overrideJson, [System.Text.UTF8Encoding]::new($false))
    $originalPath = $env:PATH
    try {
      if ($PathOverride) {
        $env:PATH = $PathOverride
      }
      $output = & $ChezmoiPath execute-template --file $script:TemplatePath `
        --override-data-file $overrideDataFile `
        --source $script:RepoHome --destination $dest 2>&1
      [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output -join "`n")
      }
    } finally {
      $env:PATH = $originalPath
      Remove-Item -Path $dest, $overrideDataFile -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe 'config.json.tmpl' -Skip:(-not $script:HasChezmoi) {

  Context 'Windows rendering with pwsh available' -Skip:(-not $script:HasPwsh) {
    BeforeAll {
      $script:Render = Invoke-Render -Os 'windows'
      $script:Config = $script:Render.Output | ConvertFrom-Json
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'delegate.command uses pwsh -NoProfile -File pointing at coderabbit-critique.ps1' {
      $script:Config.critiqueLoop.delegate.command |
        Should -Match '^pwsh -NoProfile -File ".*coderabbit-critique\.ps1"$'
    }

    It 'telemetryHook.command uses pwsh -NoProfile -File pointing at idd-critique-telemetry.ps1' {
      $script:Config.critiqueLoop.telemetryHook.command |
        Should -Match '^pwsh -NoProfile -File ".*idd-critique-telemetry\.ps1"$'
    }

    It 'delegate.mode stays combined' {
      $script:Config.critiqueLoop.delegate.mode | Should -Be 'combined'
    }
  }

  Context 'Windows rendering without pwsh on PATH (powershell.exe fallback)' {
    BeforeAll {
      # Copy the real chezmoi binary into an isolated directory holding
      # nothing else, so a PATH restricted to it (plus the system
      # directory chezmoi/Go's runtime may still need) cannot resolve
      # pwsh regardless of where this host happens to install it --
      # unlike a bare directory-of-origin restriction, which is a no-op
      # whenever chezmoi and pwsh are installed side by side (observed:
      # both under the same Homebrew bin directory on this repository's
      # own dev machine). This forces the template's own `lookPath
      # "pwsh"` check to fail, exercising the powershell.exe fallback
      # branch the pwsh-available context above cannot reach.
      #
      # $IsWindows -ne $false (not a bare truthy check): $IsWindows is a
      # PowerShell 6+ automatic variable that is $null -- not $false --
      # on Windows PowerShell 5.1, and this file only ever runs on a
      # Windows host there, so treating that $null the same as "Windows"
      # is required for a correct 5.1 Windows CI leg (mirrors the
      # 85-warn-git-bash-aslr.Tests.ps1 / 90-reconcile-claude-code.Tests.ps1
      # convention). A bare `if (-not $IsWindows)` would wrongly take the
      # Linux branch on that leg (chmod there, colon-joined PATH) and either
      # fail outright or silently exercise the wrong code path.
      $script:FakeBinDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
      New-Item -ItemType Directory -Path $script:FakeBinDir -Force | Out-Null
      $isolatedChezmoi = Join-Path $script:FakeBinDir (Split-Path -Leaf $script:ChezmoiSource)
      Copy-Item -Path $script:ChezmoiSource -Destination $isolatedChezmoi -Force
      if ($IsWindows -eq $false) {
        & chmod +x $isolatedChezmoi
      }
      # Non-Windows branch deliberately omits /usr/bin and /bin: chezmoi
      # is invoked here by its full isolated-copy path (not resolved via
      # PATH), and this template's rendering only ever shells out through
      # the `lookPath "pwsh"` builtin -- no other external command is
      # needed. Including /usr/bin or /bin would let a native (non-Homebrew)
      # Linux pwsh install (Microsoft's apt package symlinks to
      # /usr/bin/pwsh) defeat this context's purpose by letting lookPath
      # resolve pwsh after all, on a host where it wouldn't on this
      # repository's own Homebrew-based dev machine.
      $minimalPath = if ($IsWindows -ne $false) {
        "$script:FakeBinDir$([IO.Path]::PathSeparator)$([Environment]::SystemDirectory)"
      } else {
        $script:FakeBinDir
      }
      $script:Render = Invoke-Render -Os 'windows' -ChezmoiPath $isolatedChezmoi -PathOverride $minimalPath
      $script:Config = $script:Render.Output | ConvertFrom-Json
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'delegate.command falls back to powershell.exe -NoProfile -File pointing at coderabbit-critique.ps1' {
      $script:Config.critiqueLoop.delegate.command |
        Should -Match '^powershell\.exe -NoProfile -File ".*coderabbit-critique\.ps1"$'
    }

    It 'telemetryHook.command falls back to powershell.exe -NoProfile -File pointing at idd-critique-telemetry.ps1' {
      $script:Config.critiqueLoop.telemetryHook.command |
        Should -Match '^powershell\.exe -NoProfile -File ".*idd-critique-telemetry\.ps1"$'
    }
  }

  Context 'non-Windows rendering (mirrors tests/bash/idd-skill-config-tmpl.bats coverage)' {
    BeforeAll {
      $script:Render = Invoke-Render -Os 'linux'
      $script:Config = $script:Render.Output | ConvertFrom-Json
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'delegate.command is single-quoted and unaffected by the Windows branch' {
      $script:Config.critiqueLoop.delegate.command | Should -Match "^'.*coderabbit-critique'$"
    }

    It 'telemetryHook has no mode field' {
      $script:Config.critiqueLoop.telemetryHook.PSObject.Properties.Name |
        Should -Not -Contain 'mode'
    }
  }
}
