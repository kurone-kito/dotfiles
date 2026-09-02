# Tests for the chezmoi modify-template rendering of
# home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/modify_settings.json
# (see #349, built on #347's resync), which merges Windows Terminal's
# live settings.json instead of overwriting it wholesale.
#
# Renders via a real `chezmoi apply` run against a scratch source/
# destination pair (mirrors sshd-config-tmpl.Tests.ps1 /
# winget-user-path-packages-tmpl.Tests.ps1's real-invocation pattern),
# not `chezmoi execute-template`: `.chezmoi.stdin` -- the destination's
# current content, which this modify-template parses and merges -- is
# populated only during an actual modify-script run inside `chezmoi
# apply`, not during isolated template execution.
#
# Skipped entirely when chezmoi is not available on PATH (e.g., minimal
# Windows runners).

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoHome = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home' | Resolve-Path
  $script:TemplateSourceDir = Join-Path $script:RepoHome (
    Join-Path 'AppData' (
      Join-Path 'Local' (
        Join-Path 'Packages' (
          Join-Path 'Microsoft.WindowsTerminal_8wekyb3d8bbwe' 'LocalState'
        )
      )
    )
  )
  $script:TemplatePath = Join-Path $script:TemplateSourceDir 'modify_settings.json'

  # The four profiles.list GUIDs this repository owns -- kept in sync
  # with the template's own $managedProfileGuids list and its header
  # comment's rationale (Windows PowerShell, the Japanese Command
  # Prompt entry, Azure Cloud Shell, and the user-defined PowerShell
  # profile #347 resynced).
  $script:ManagedGuids = @(
    '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
    '{0caa0dad-35be-5f56-a8ff-afceeeaa6101}'
    '{b453ae62-4e3d-5e58-b989-0a998ec441b8}'
    '{ab98be26-311f-4211-a628-661396a1647a}'
  )

  function Invoke-ModifyTemplateApply {
    param(
      # $null means "no seed file" (destination does not exist yet,
      # exercising the empty-.chezmoi.stdin path). A string seeds
      # dest/settings.json with that exact content before applying.
      [string] $SeedJson
    )
    $scratchSource = Join-Path ([IO.Path]::GetTempPath()) ("wt-settings-src-{0}" -f [guid]::NewGuid())
    $scratchDest = Join-Path ([IO.Path]::GetTempPath()) ("wt-settings-dest-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $scratchSource -Force | Out-Null
    New-Item -ItemType Directory -Path $scratchDest -Force | Out-Null
    # Copy the real template into a flat scratch source root: a
    # top-level file in the source root maps directly to a same-named
    # file in the destination root, so this reproduces the real
    # modify_settings.json -> settings.json mapping without needing to
    # recreate the full AppData/... directory nesting.
    Copy-Item -Path $script:TemplatePath -Destination (Join-Path $scratchSource 'modify_settings.json') -Force
    $destSettingsPath = Join-Path $scratchDest 'settings.json'
    if ($null -ne $SeedJson) {
      [System.IO.File]::WriteAllText($destSettingsPath, $SeedJson, [System.Text.UTF8Encoding]::new($false))
    }
    # On Windows PowerShell 5.1, `2>&1` turns a native command's stderr
    # lines into terminating ErrorRecord objects whenever
    # $ErrorActionPreference is 'Stop' (as this repository's CI job
    # sets it) -- the invalid-JSON case below writes to stderr and
    # exits non-zero by design, which would otherwise abort this
    # function before ExitCode/Content can be captured. Temporarily
    # relax to 'Continue' around just the native invocation, restoring
    # the caller's preference afterward even if something still throws.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $output = & chezmoi apply --source $scratchSource --destination $scratchDest --force 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }
    try {
      # Read via .NET with an explicit UTF-8 (no BOM) decoder rather
      # than Get-Content -Raw: chezmoi writes the rendered file as
      # UTF-8 without a BOM, but Get-Content's default encoding
      # differs between Windows PowerShell 5.1 (a legacy codepage
      # absent a BOM) and pwsh 7+ (UTF-8), which would otherwise
      # mis-decode the non-ASCII Japanese profile name every render
      # includes on Windows PowerShell 5.1.
      $content = if (Test-Path $destSettingsPath) {
        [System.IO.File]::ReadAllText($destSettingsPath, [System.Text.UTF8Encoding]::new($false))
      } else {
        $null
      }
      [pscustomobject]@{
        ExitCode = $exitCode
        Output   = ($output -join "`n")
        Content  = $content
      }
    } finally {
      Remove-Item -Path $scratchSource, $scratchDest -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe 'modify_settings.json' -Skip:(-not $script:HasChezmoi) {

  Context 'empty destination (fresh machine, no prior settings.json)' {
    BeforeAll {
      $script:Render = Invoke-ModifyTemplateApply -SeedJson $null
      # Best-effort: a BeforeAll exception aborts every It in this
      # Context before 'renders successfully'/'produces valid JSON' can
      # report a clear, individual failure. Fall back to $null instead,
      # so those two assertions still run and the rest fail on a null
      # comparison rather than an opaque setup exception.
      try {
        $script:Parsed = $script:Render.Content | ConvertFrom-Json -ErrorAction Stop
      } catch {
        $script:Parsed = $null
      }
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'produces valid JSON' {
      { $script:Render.Content | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'includes all four managed profiles.list GUIDs' {
      ($script:Parsed.profiles.list.guid | Sort-Object) | Should -Be ($script:ManagedGuids | Sort-Object)
    }

    It 'sets defaultProfile to the repository-owned PowerShell profile' {
      $script:Parsed.defaultProfile | Should -Be '{ab98be26-311f-4211-a628-661396a1647a}'
    }
  }

  Context 'rendering against an altered target with an unmanaged profile' {
    BeforeAll {
      $seed = @{
        '$help'                             = 'https://aka.ms/terminal-documentation'
        '$schema'                           = 'https://aka.ms/terminal-profiles-schema'
        actions                             = @()
        'compatibility.allowHeadless'       = $false
        copyFormatting                      = 'all'
        copyOnSelect                        = $true
        defaultProfile                      = '{deadbeef-0000-0000-0000-000000000000}'
        'experimental.enableColorSelection' = $false
        keybindings                         = @()
        newTabMenu                          = @()
        schemes                             = @(@{ name = 'MyCustomScheme' })
        themes                              = @(@{ name = 'MyCustomTheme' })
        profiles                            = @{
          defaults = @{ opacity = 50; useAcrylic = $false }
          list     = @(
            @{
              commandline = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
              guid        = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
              hidden      = $true
              name        = 'RENAMED Windows PowerShell'
            },
            @{
              guid   = '{ubuntu-guid-not-managed-1234}'
              hidden = $false
              name   = 'Ubuntu'
              source = 'Windows.Terminal.Wsl'
            }
          )
        }
        useAcrylicInTabRow                  = $false
      }
      $script:Render = Invoke-ModifyTemplateApply -SeedJson ($seed | ConvertTo-Json -Depth 10)
      # Best-effort, mirroring the empty-destination Context above.
      try {
        $script:Parsed = $script:Render.Content | ConvertFrom-Json -ErrorAction Stop
      } catch {
        $script:Parsed = $null
      }
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'restores this repository''s values for altered top-level managed keys' {
      $script:Parsed.defaultProfile | Should -Be '{ab98be26-311f-4211-a628-661396a1647a}'
      $script:Parsed.'compatibility.allowHeadless' | Should -BeTrue
      $script:Parsed.'experimental.enableColorSelection' | Should -BeTrue
    }

    It 'restores this repository''s values for altered profiles.defaults' {
      $script:Parsed.profiles.defaults.opacity | Should -Be 78
      $script:Parsed.profiles.defaults.useAcrylic | Should -BeTrue
    }

    It 'restores the managed profiles.list entry (matched by guid) even after a rename' {
      $managed = $script:Parsed.profiles.list | Where-Object { $_.guid -eq '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}' }
      $managed.name | Should -Be 'Windows PowerShell'
    }

    It 'leaves the unmanaged profiles.list entry (unrecognized guid) present in the output' {
      $extra = $script:Parsed.profiles.list | Where-Object { $_.guid -eq '{ubuntu-guid-not-managed-1234}' }
      $extra | Should -Not -BeNullOrEmpty
      $extra.name | Should -Be 'Ubuntu'
    }

    It 'preserves unmanaged top-level keys (schemes/themes) from the incoming file' {
      $script:Parsed.schemes[0].name | Should -Be 'MyCustomScheme'
      $script:Parsed.themes[0].name | Should -Be 'MyCustomTheme'
    }
  }

  Context 'rendering against a malformed profiles.list (valid JSON, unexpected shape)' {
    It 'drops a non-object profiles.list entry instead of preserving it verbatim' {
      $seedJson = '{"profiles":{"list":[42,{"guid":"{ubuntu-guid-not-managed-1234}","name":"Ubuntu"}]}}'
      $render = Invoke-ModifyTemplateApply -SeedJson $seedJson
      $render.ExitCode | Should -Be 0
      $parsed = $render.Content | ConvertFrom-Json
      # The bare number must not appear anywhere in profiles.list; every
      # entry must be a genuine object with its own guid.
      ($parsed.profiles.list | ForEach-Object { $_.guid }) | Should -Not -Contain $null
      $parsed.profiles.list.Count | Should -Be 5
      ($parsed.profiles.list | Where-Object { $_.guid -eq '{ubuntu-guid-not-managed-1234}' }) | Should -Not -BeNullOrEmpty
    }

    It 'falls back to the managed profiles.list only when the incoming "list" is not an array' {
      $render = Invoke-ModifyTemplateApply -SeedJson '{"profiles":{"list":"not-a-list"}}'
      $render.ExitCode | Should -Be 0
      $parsed = $render.Content | ConvertFrom-Json
      ($parsed.profiles.list.guid | Sort-Object) | Should -Be ($script:ManagedGuids | Sort-Object)
    }

    It 'drops an object profiles.list entry that has no guid at all' {
      $seedJson = '{"profiles":{"list":[{"name":"NoGuidProfile"},{"guid":"{ubuntu-guid-not-managed-1234}","name":"Ubuntu"}]}}'
      $render = Invoke-ModifyTemplateApply -SeedJson $seedJson
      $render.ExitCode | Should -Be 0
      $parsed = $render.Content | ConvertFrom-Json
      $parsed.profiles.list.Count | Should -Be 5
      ($parsed.profiles.list | Where-Object { $_.name -eq 'NoGuidProfile' }) | Should -BeNullOrEmpty
      ($parsed.profiles.list | Where-Object { $_.guid -eq '{ubuntu-guid-not-managed-1234}' }) | Should -Not -BeNullOrEmpty
    }

    It 'drops an object profiles.list entry whose guid is an empty string' {
      $seedJson = '{"profiles":{"list":[{"guid":"","name":"EmptyGuid"},{"guid":"{ubuntu-guid-not-managed-1234}","name":"Ubuntu"}]}}'
      $render = Invoke-ModifyTemplateApply -SeedJson $seedJson
      $render.ExitCode | Should -Be 0
      $parsed = $render.Content | ConvertFrom-Json
      $parsed.profiles.list.Count | Should -Be 5
      ($parsed.profiles.list | Where-Object { $_.name -eq 'EmptyGuid' }) | Should -BeNullOrEmpty
    }
  }

  Context 'rendering against a non-object top-level value (valid JSON, unexpected shape)' {
    It 'falls back to the complete managed document for a top-level array' {
      $render = Invoke-ModifyTemplateApply -SeedJson '[1,2,3]'
      $render.ExitCode | Should -Be 0
      $parsed = $render.Content | ConvertFrom-Json
      ($parsed.profiles.list.guid | Sort-Object) | Should -Be ($script:ManagedGuids | Sort-Object)
    }

    It 'falls back to the complete managed document for a top-level string' {
      $render = Invoke-ModifyTemplateApply -SeedJson '"oops"'
      $render.ExitCode | Should -Be 0
      $parsed = $render.Content | ConvertFrom-Json
      $parsed.defaultProfile | Should -Be '{ab98be26-311f-4211-a628-661396a1647a}'
    }

    It 'falls back to the complete managed document for a top-level number' {
      $render = Invoke-ModifyTemplateApply -SeedJson '42'
      $render.ExitCode | Should -Be 0
      $parsed = $render.Content | ConvertFrom-Json
      $parsed.defaultProfile | Should -Be '{ab98be26-311f-4211-a628-661396a1647a}'
    }
  }

  Context 'rendering against invalid JSON input' {
    BeforeAll {
      $script:SeedContent = 'not { valid json'
      $script:Render = Invoke-ModifyTemplateApply -SeedJson $script:SeedContent
    }

    It 'fails rather than succeeding' {
      $script:Render.ExitCode | Should -Not -Be 0
    }

    It 'does not overwrite the target with empty or truncated content' {
      $script:Render.Content | Should -Be $script:SeedContent
    }
  }
}
