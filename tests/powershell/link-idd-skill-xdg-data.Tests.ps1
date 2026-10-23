# Tests for the run_after_83-link-idd-skill-xdg-data chezmoi script: links a
# customized XDG_DATA_HOME/idd-skill to the deployed IDD payload data root.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/run_after_83-link-idd-skill-xdg-data.ps1'
  $versionSource = Join-Path $PSScriptRoot `
    '../../home/dot_local/share/idd-skill/symlink_current'
  $script:PayloadVersion = (Get-Content -LiteralPath $versionSource -Raw).Trim()

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
    $dir = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' (Join-Path 'idd-skill' $script:PayloadVersion)))
    $entry = Join-Path (Join-Path $dir 'user-global') 'entry.md'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $entry) -Force
    Set-Content -LiteralPath $entry -Value 'managed payload marker'
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
    Test-Path -LiteralPath $env:XDG_DATA_HOME | Should -BeFalse
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
    $env:XDG_DATA_HOME = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' (Join-Path 'idd-skill' $script:PayloadVersion)))

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
    $env:XDG_DATA_HOME = Join-Path $alias $script:PayloadVersion

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path $script:PayloadVersion 'idd-skill')) |
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
    $env:XDG_DATA_HOME = Join-Path $chain $script:PayloadVersion

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path $script:PayloadVersion 'idd-skill')) |
      Should -BeFalse
  }

  It 'no-ops when XDG_DATA_HOME reaches the deployed tree through a link to its parent' {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $share = Join-Path $HOME (Join-Path '.local' 'share')
    $alias = Join-Path $TestDrive 'alias-share'
    New-TestDirectoryLink $alias $share
    $env:XDG_DATA_HOME = Join-Path $alias (Join-Path 'idd-skill' $script:PayloadVersion)

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path $script:PayloadVersion 'idd-skill')) |
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
    $env:XDG_DATA_HOME = Join-Path $relative $script:PayloadVersion

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedRoot (Join-Path $script:PayloadVersion 'idd-skill')) |
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

  It 'warns and leaves a file in place when XDG_DATA_HOME is an existing file' {
    Write-DeployedPayload
    $file = Join-Path $TestDrive 'not-a-directory'
    Set-Content -LiteralPath $file -Value 'keep'
    $env:XDG_DATA_HOME = $file

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*is not a directory*'
    Get-Content -LiteralPath $file -Raw | Should -BeLike '*keep*'
  }

  It 'warns and does not abort when XDG_DATA_HOME names a drive that does not exist' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1) })
    $free = (90..65) | ForEach-Object { [string][char]$_ } | Where-Object { $used -notcontains $_ } | Select-Object -First 1
    if (-not $free) {
      Set-ItResult -Skipped -Because 'no free drive letter on this host'
      return
    }
    $env:XDG_DATA_HOME = "$($free):\idd-data"

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike "*could not create $($free):\idd-data*"
  }

  It 'refuses an XDG_DATA_HOME given as a device path on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = "\\?\$(Join-Path $TestDrive 'dev')"

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*device paths*'
    Test-Path -LiteralPath (Join-Path $TestDrive 'dev') | Should -BeFalse
  }

  It 'refuses an XDG_DATA_HOME given as a device path with forward slashes on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = '\\?/' + (Join-Path $TestDrive 'dev-slash').Replace('\', '/')

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*device paths*'
    Test-Path -LiteralPath (Join-Path $TestDrive 'dev-slash') | Should -BeFalse
  }

  It 'creates the current pointer as a directory junction on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))

    & $script:Subject

    $current = Get-Item -LiteralPath (Join-Path $deployedRoot 'current') -Force
    $current.LinkType | Should -Be 'Junction'
    $current.Target | Should -Contain (Join-Path $deployedRoot $script:PayloadVersion)
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
    $env:XDG_DATA_HOME = Join-Path $deployedLong $script:PayloadVersion

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*resolves to the deployed payload*'
    Test-Path -LiteralPath (Join-Path $deployedLong (Join-Path $script:PayloadVersion 'idd-skill')) | Should -BeFalse
  }

  It 'advances a current junction from a previous managed version on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $previous = Join-Path $deployedRoot '0.16.0'
    $previousEntry = Join-Path (Join-Path $previous 'user-global') 'entry.md'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $previousEntry) -Force
    Set-Content -LiteralPath $previousEntry -Value 'previous managed payload marker'
    $currentPointer = Join-Path $deployedRoot 'current'
    $null = New-Item -ItemType Junction -Path $currentPointer -Target $previous
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'

    $warnings = & $script:Subject 3>&1

    @($warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
      Should -Be 0
    (Get-Item -LiteralPath $currentPointer -Force).Target |
      Should -Contain (Join-Path $deployedRoot $script:PayloadVersion)
  }

  It 'restores the previous current link when the replacement junction fails on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $previous = Join-Path $deployedRoot '0.16.0'
    $previousEntry = Join-Path (Join-Path $previous 'user-global') 'entry.md'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $previousEntry) -Force
    Set-Content -LiteralPath $previousEntry -Value 'previous managed payload marker'
    $currentPointer = Join-Path $deployedRoot 'current'
    $null = New-Item -ItemType Junction -Path $currentPointer -Target $previous
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'
    $newTarget = Join-Path $deployedRoot $script:PayloadVersion

    Mock New-Item { throw 'simulated junction creation failure' } -ParameterFilter {
      $ItemType -eq 'Junction' -and $Path -eq $currentPointer -and $Target -eq $newTarget
    }

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*restored a junction to 0.16.0*'
    (Get-Item -LiteralPath $currentPointer -Force).Target | Should -Contain $previous
  }

  It 'restores a managed symbolic link as a junction when replacement fails on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $previous = Join-Path $deployedRoot '0.16.0'
    $previousEntry = Join-Path (Join-Path $previous 'user-global') 'entry.md'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $previousEntry) -Force
    Set-Content -LiteralPath $previousEntry -Value 'previous managed payload marker'
    $currentPointer = Join-Path $deployedRoot 'current'
    try {
      $null = New-Item -ItemType SymbolicLink -Path $currentPointer -Target $previous -ErrorAction Stop
    } catch {
      Set-ItResult -Skipped -Because 'symbolic-link creation needs Windows developer mode or elevation'
      return
    }
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'
    $newTarget = Join-Path $deployedRoot $script:PayloadVersion

    Mock New-Item { throw 'simulated junction creation failure' } -ParameterFilter {
      $ItemType -eq 'Junction' -and $Path -eq $currentPointer -and $Target -eq $newTarget
    }

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike '*restored a junction to 0.16.0*'
    $restored = Get-Item -LiteralPath $currentPointer -Force
    $restored.LinkType | Should -Be 'Junction'
    $restored.Target | Should -Contain $previous
  }

  It 'keeps a current junction that points at an unrelated version on Windows' -Skip:($IsWindows -eq $false) {
    Write-DeployedPayload
    $deployedRoot = Join-Path $HOME (Join-Path '.local' (Join-Path 'share' 'idd-skill'))
    $other = Join-Path $deployedRoot '0.15.0'
    $null = New-Item -ItemType Directory -Path $other -Force
    $currentPointer = Join-Path $deployedRoot 'current'
    $null = New-Item -ItemType Junction -Path $currentPointer -Target $other
    $env:XDG_DATA_HOME = Join-Path $TestDrive 'custom-data'

    $warnings = & $script:Subject 3>&1

    $warnings | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message | Should -BeLike "*points at*not $script:PayloadVersion*"
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
