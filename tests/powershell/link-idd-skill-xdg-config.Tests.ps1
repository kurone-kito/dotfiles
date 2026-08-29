# Tests for the run_after_82-link-idd-skill-xdg-config chezmoi script:
# bridges the rendered IDD critique-delegate config to a customized
# XDG_CONFIG_HOME.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/run_after_82-link-idd-skill-xdg-config.ps1'

  function script:Write-RenderedConfig {
    $dir = Join-Path $HOME (Join-Path '.config' 'idd-skill')
    $null = New-Item -ItemType Directory -Path $dir -Force
    Set-Content -Path (Join-Path $dir 'config.json') `
      -Value '{"critiqueLoop":{"delegate":{"command":"x","mode":"combined"}}}'
  }
}

Describe 'link-idd-skill-xdg-config' {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalXdg = $env:XDG_CONFIG_HOME
    # Use $TestDrive (Pester's real resolved filesystem path), not the
    # 'TestDrive:' PSDrive-prefixed string -- New-Item -ItemType
    # SymbolicLink needs a real path for -Target. On real Windows, passing
    # the literal "TestDrive:\..." string through fails with "The
    # filename, directory name, or volume label syntax is incorrect"
    # (colons are only valid at drive-letter position in an NTFS path).
    $script:TestHome = Join-Path $TestDrive 'home'
    if (Test-Path -LiteralPath $script:TestHome) {
      Remove-Item -LiteralPath $script:TestHome -Recurse -Force
    }
    $customXdg = Join-Path $TestDrive 'custom-xdg'
    if (Test-Path -LiteralPath $customXdg) {
      Remove-Item -LiteralPath $customXdg -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $script:TestHome -Force
    Set-Variable -Name HOME -Value $script:TestHome -Scope Global -Force
    Remove-Item Env:\XDG_CONFIG_HOME -ErrorAction SilentlyContinue
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    if ($null -eq $script:OriginalXdg) {
      Remove-Item Env:\XDG_CONFIG_HOME -ErrorAction SilentlyContinue
    } else {
      $env:XDG_CONFIG_HOME = $script:OriginalXdg
    }
  }

  It 'no-ops when XDG_CONFIG_HOME is unset' {
    Write-RenderedConfig

    & $script:Subject

    $LASTEXITCODE | Should -BeIn @(0, $null)
  }

  It 'no-ops when the rendered config does not exist yet' {
    $env:XDG_CONFIG_HOME = Join-Path $TestDrive 'custom-xdg'

    & $script:Subject

    Test-Path -LiteralPath (Join-Path $env:XDG_CONFIG_HOME 'idd-skill') | Should -BeFalse
  }

  It 'symlinks the rendered config into a custom XDG_CONFIG_HOME' {
    Write-RenderedConfig
    $env:XDG_CONFIG_HOME = Join-Path $TestDrive 'custom-xdg'

    & $script:Subject

    $target = Join-Path $env:XDG_CONFIG_HOME (Join-Path 'idd-skill' 'config.json')
    $rendered = Join-Path $HOME (Join-Path '.config' (Join-Path 'idd-skill' 'config.json'))
    $item = Get-Item -LiteralPath $target
    $item.LinkType | Should -Be 'SymbolicLink'
    $item.Target | Should -Contain $rendered
  }

  It 'is idempotent when the symlink already points at the rendered config' {
    Write-RenderedConfig
    $env:XDG_CONFIG_HOME = Join-Path $TestDrive 'custom-xdg'
    & $script:Subject

    { & $script:Subject } | Should -Not -Throw
  }

  It 'does not overwrite a symlink pointing at a different target' {
    Write-RenderedConfig
    $env:XDG_CONFIG_HOME = Join-Path $TestDrive 'custom-xdg'
    $targetDir = Join-Path $env:XDG_CONFIG_HOME 'idd-skill'
    $null = New-Item -ItemType Directory -Path $targetDir -Force
    $otherManaged = Join-Path $TestDrive 'other-managed-config.json'
    Set-Content -Path $otherManaged -Value '{"other":true}'
    $target = Join-Path $targetDir 'config.json'
    $null = New-Item -ItemType SymbolicLink -Path $target -Target $otherManaged

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*not overwriting*'
    (Get-Item -LiteralPath $target).Target | Should -Contain $otherManaged
  }

  It 'does not overwrite a real (non-symlink) file already at the target' {
    Write-RenderedConfig
    $env:XDG_CONFIG_HOME = Join-Path $TestDrive 'custom-xdg'
    $targetDir = Join-Path $env:XDG_CONFIG_HOME 'idd-skill'
    $null = New-Item -ItemType Directory -Path $targetDir -Force
    Set-Content -Path (Join-Path $targetDir 'config.json') -Value '{"pre-existing":true}'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*not overwriting*'
    Get-Content -LiteralPath (Join-Path $targetDir 'config.json') -Raw |
      Should -BeLike '*pre-existing*'
  }
}
