# Tests for the run_after_83-link-idd-skill-xdg-data chezmoi script: links a
# customized XDG_DATA_HOME/idd-skill to the deployed IDD payload data root.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/run_after_83-link-idd-skill-xdg-data.ps1'

  # The directory link type this host can create: a symbolic link where the
  # privilege allows it, otherwise a junction. Probed once per Pester run.
  $probeTarget = Join-Path $TestDrive 'link-probe-target'
  $null = New-Item -ItemType Directory -Path $probeTarget -Force
  try {
    $null = New-Item -ItemType SymbolicLink -Path (Join-Path $TestDrive 'link-probe') -Target $probeTarget -ErrorAction Stop
    $script:DirectoryLinkType = 'SymbolicLink'
  } catch {
    $script:DirectoryLinkType = 'Junction'
  }

  # A directory link: a symbolic link where the host allows it, else a directory
  # junction, which the script also falls back to on Windows.
  function script:New-TestDirectoryLink([string]$Path, [string]$Target) {
    try {
      $null = New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop
    } catch {
      $null = New-Item -ItemType Junction -Path $Path -Target $Target
    }
  }

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
    $item.LinkType | Should -Be $script:DirectoryLinkType
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
      Should -Be $script:DirectoryLinkType
  }

  It 'no-ops when XDG_DATA_HOME is inside the deployed data root' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' (Join-Path 'idd-skill' '0.16.0')))

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $env:XDG_DATA_HOME 'idd-skill') | Should -BeFalse
  }

  It 'no-ops when XDG_DATA_HOME reaches the deployed tree through a link' {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $alias = Join-Path $TestDrive 'alias-root'
    New-TestDirectoryLink $alias $deployedRoot
    $env:XDG_DATA_HOME = Join-Path $alias '0.16.0'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path '0.16.0' 'idd-skill')) |
      Should -BeFalse
  }

  It 'no-ops when XDG_DATA_HOME is the deployed data root itself' {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $env:XDG_DATA_HOME = $deployedRoot

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot 'idd-skill') | Should -BeFalse
  }

  It 'no-ops when XDG_DATA_HOME reaches the deployed tree through a chain of links' {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $hop = Join-Path $TestDrive 'hop-root'
    $chain = Join-Path $TestDrive 'chain-root'
    New-TestDirectoryLink $hop $deployedRoot
    New-TestDirectoryLink $chain $hop
    $env:XDG_DATA_HOME = Join-Path $chain '0.16.0'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path '0.16.0' 'idd-skill')) |
      Should -BeFalse
  }

  It 'no-ops when XDG_DATA_HOME reaches the deployed tree through a link to its parent' {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $share = Join-Path $HOME (Join-Path '.local' 'share')
    $alias = Join-Path $TestDrive 'alias-share'
    New-TestDirectoryLink $alias $share
    $env:XDG_DATA_HOME = Join-Path $alias (Join-Path 'idd-skill' '0.16.0')

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path '0.16.0' 'idd-skill')) |
      Should -BeFalse
  }

  # PowerShell 5.1 resolves a relative -Target against the current directory, so
  # the link is not made there. This case runs on PowerShell 7 only.
  It 'no-ops when XDG_DATA_HOME reaches the deployed tree through a relative link' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $relative = Join-Path $TestDrive 'relative-root'
    if ($script:DirectoryLinkType -ne 'SymbolicLink') {
      Set-ItResult -Skipped -Because 'a relative symbolic link needs privilege on this host'
      return
    }
    $null = New-Item -ItemType SymbolicLink -Path $relative -ErrorAction Stop `
      -Target (Join-Path 'home' (Join-Path '.local' (Join-Path 'share' 'idd-skill')))
    $env:XDG_DATA_HOME = Join-Path $relative '0.16.0'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path '0.16.0' 'idd-skill')) |
      Should -BeFalse
  }

  # PowerShell 5.1 New-Item refuses a link whose target does not exist yet, and a
  # loop needs one. This case runs on PowerShell 7 only.
  It 'refuses an XDG_DATA_HOME whose links form a loop' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
    Write-DeployedPayload
    $loopA = Join-Path $TestDrive 'loop-a'
    $loopB = Join-Path $TestDrive 'loop-b'
    if ($script:DirectoryLinkType -ne 'SymbolicLink') {
      Set-ItResult -Skipped -Because 'a symbolic link loop needs privilege on this host'
      return
    }
    $null = New-Item -ItemType SymbolicLink -Path $loopA -Target $loopB -ErrorAction Stop
    $null = New-Item -ItemType SymbolicLink -Path $loopB -Target $loopA -ErrorAction Stop
    $env:XDG_DATA_HOME = Join-Path $loopA 'custom'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*nest too deeply*'
  }

  It 'stays silent when XDG_DATA_HOME is the default data home' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $HOME (Join-Path '.local' 'share')

    $warnings = & $script:Subject 3>&1

    @($warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
      Should -Be 0
  }

  It 'pins the same version as the symlink_current source' {
    $source = Join-Path $PSScriptRoot '../../home/dot_local/share/idd-skill/symlink_current'
    $version = (Get-Content -LiteralPath $source -Raw).Trim()
    Get-Content -LiteralPath $script:Subject -Raw |
      Should -Match ('(?m)^\$version = ' + [regex]::Escape("'$version'"))
  }

  It 'creates the current pointer as a directory junction on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))

    & $script:Subject

    $current = Get-Item -LiteralPath (Join-Path $deployedRoot 'current') -Force
    $current.LinkType | Should -Be 'Junction'
    $current.Target | Should -Contain (Join-Path $deployedRoot '0.16.0')
  }

  It 'refuses the deployed root under its long name when HOME is given in 8.3 short form on Windows' -Skip:($IsWindows -eq $false) {
    $longHome = [System.IO.Path]::GetFullPath($HOME)
    $shortHome = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($longHome).ShortPath
    if ($shortHome -eq $longHome) {
      Set-ItResult -Skipped -Because 'this volume has no 8.3 short names'
      return
    }
    Set-Variable -Name HOME -Value $shortHome -Scope Global -Force
    Write-DeployedPayload
    $deployedLong = Join-Path $longHome (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $env:XDG_DATA_HOME = Join-Path $deployedLong '0.16.0'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedLong (Join-Path '0.16.0' 'idd-skill')) | Should -BeFalse
  }

  It 'keeps a current junction that points at another version on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $other = Join-Path $deployedRoot '0.15.0'
    $null = New-Item -ItemType Directory -Path $other -Force
    $currentPointer = Join-Path $deployedRoot 'current'
    $null = New-Item -ItemType Junction -Path $currentPointer -Target $other
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*points at*not 0.16.0*'
    (Get-Item -LiteralPath $currentPointer -Force).Target | Should -Contain $other
  }

  It 'does not replace a real current directory on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $currentPointer = Join-Path $deployedRoot 'current'
    $null = New-Item -ItemType Directory -Path $currentPointer -Force
    Set-Content -Path (Join-Path $currentPointer 'marker.txt') -Value 'pre-existing'
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*is not a link*'
    Get-Content -LiteralPath (Join-Path $currentPointer 'marker.txt') -Raw |
      Should -BeLike '*pre-existing*'
  }

  It 'does not overwrite a link pointing at a different target' {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'
    $target = Join-Path $env:XDG_DATA_HOME 'idd-skill'
    $null = New-Item -ItemType Directory -Path $env:XDG_DATA_HOME -Force
    $other = Join-Path $TestDrive 'other-managed-data'
    $null = New-Item -ItemType Directory -Path $other -Force
    New-TestDirectoryLink $target $other

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
