# Tests for the run_after_83-link-idd-skill-xdg-data chezmoi script: links a
# customized XDG_DATA_HOME/idd-skill to the deployed IDD payload data root.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/run_after_83-link-idd-skill-xdg-data.ps1'

  function script:Write-DeployedPayload {
    $dir = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' (Join-Path 'idd-skill' '0.16.0')))
    $null = New-Item -ItemType Directory -Path $dir -Force
  }
}

Describe 'link-idd-skill-xdg-data' {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:OriginalXdg = $env:XDG_DATA_HOME
    # Use $TestDrive's resolved filesystem path, not the 'TestDrive:' PSDrive
    # string: New-Item -ItemType SymbolicLink needs a real path for -Target.
    $script:TestHome = Join-Path $TestDrive 'home'
    if (Test-Path -LiteralPath $script:TestHome) {
      Remove-Item -LiteralPath $script:TestHome -Recurse -Force
    }
    $customData = Join-Path $TestDrive 'custom-data'
    if (Test-Path -LiteralPath $customData) {
      Remove-Item -LiteralPath $customData -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $script:TestHome -Force
    Set-Variable -Name HOME -Value $script:TestHome -Scope Global -Force
    Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    if ($null -eq $script:OriginalXdg) {
      Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue
    } else {
      $env:XDG_DATA_HOME = $script:OriginalXdg
    }
  }

  It 'no-ops when XDG_DATA_HOME is unset' {
    Write-DeployedPayload

    { & $script:Subject } | Should -Not -Throw
    Test-Path -LiteralPath (Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))) |
      Should -BeTrue
  }

  It 'no-ops when the deployed data root does not exist yet' {
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'

    & $script:Subject

    Get-Item -LiteralPath (Join-Path $env:XDG_DATA_HOME 'idd-skill') -Force `
      -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
  }

  It 'no-ops when XDG_DATA_HOME is a relative path' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = 'relative-data'

    { & $script:Subject } | Should -Not -Throw
    Test-Path -LiteralPath (Join-Path 'relative-data' 'idd-skill') | Should -BeFalse
  }

  It 'symlinks the deployed data root into a custom XDG_DATA_HOME' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'

    & $script:Subject

    $target = Join-Path $env:XDG_DATA_HOME 'idd-skill'
    $rendered = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $item = Get-Item -LiteralPath $target
    $item.LinkType | Should -Be 'SymbolicLink'
    $item.Target | Should -Contain $rendered
  }

  It 'is idempotent when the link already points at the deployed data root' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'
    & $script:Subject

    $warnings = & $script:Subject 3>&1

    @($warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
      Should -Be 0
    (Get-Item -LiteralPath (Join-Path $env:XDG_DATA_HOME 'idd-skill')).LinkType |
      Should -Be 'SymbolicLink'
  }

  It 'no-ops when XDG_DATA_HOME is inside the deployed data root' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' (Join-Path 'idd-skill' '0.16.0')))

    { & $script:Subject } | Should -Not -Throw
    Test-Path -LiteralPath (Join-Path $env:XDG_DATA_HOME 'idd-skill') | Should -BeFalse
  }

  It 'no-ops when XDG_DATA_HOME reaches the deployed tree through a link' {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $alias = Join-Path $TestDrive 'alias-root'
    $null = New-Item -ItemType SymbolicLink -Path $alias -Target $deployedRoot
    $env:XDG_DATA_HOME = Join-Path $alias '0.16.0'

    { & $script:Subject 3>$null } | Should -Not -Throw
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path '0.16.0' 'idd-skill')) |
      Should -BeFalse
  }

  It 'does not overwrite a link pointing at a different target' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'
    $target = Join-Path $env:XDG_DATA_HOME 'idd-skill'
    $null = New-Item -ItemType Directory -Path $env:XDG_DATA_HOME -Force
    $other = Join-Path $TestDrive 'other-managed-data'
    $null = New-Item -ItemType Directory -Path $other -Force
    $null = New-Item -ItemType SymbolicLink -Path $target -Target $other

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*not overwriting*'
    (Get-Item -LiteralPath $target).Target | Should -Contain $other
  }

  It 'does not overwrite a real directory already at the target' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'
    $target = Join-Path $env:XDG_DATA_HOME 'idd-skill'
    $null = New-Item -ItemType Directory -Path $target -Force
    Set-Content -Path (Join-Path $target 'marker.txt') -Value 'pre-existing'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*not overwriting*'
    Get-Content -LiteralPath (Join-Path $target 'marker.txt') -Raw | Should -BeLike '*pre-existing*'
  }

  It 'is listed in .chezmoiignore.tmpl' {
    $ignoreFile = Join-Path $PSScriptRoot '../../home/.chezmoiignore.tmpl'
    $lines = Get-Content $ignoreFile

    $lines | Should -Contain '83-link-idd-skill-xdg-data.sh'
    $lines | Should -Contain '83-link-idd-skill-xdg-data.ps1'
  }
}
