# Tests for the PowerShell profile conf.d loader and prompt setup.
# Uses a controlled, empty conf.d directory (via a $HOME override) so
# real conf.d scripts never run — only profile.ps1's own prompt/zoxide
# wiring below the loader loop is exercised.
# Exercises: the PSReadLine-readiness gate around the Starship
# transient-prompt function, and the zoxide-after-Starship init order.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell'
  ) 'profile.ps1'

  # A stand-in starship executable, written as a script so it can be launched
  # by path. It logs every call. For `init` it prints a line that records the
  # call in $script:CallOrder, the way the real init module would run.
  function New-StarshipStandIn {
    param([string] $Dir, [string] $LogPath)
    $path = Join-Path $Dir 'starship-standin.ps1'
    $template = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)
Add-Content -LiteralPath '__LOG__' -Value ('starship ' + ($Arguments -join ' '))
if ($Arguments[0] -eq 'init') { '$script:CallOrder += ''resolved-init''' }
'@
    $body = $template.Replace('__LOG__', ($LogPath -replace "'", "''"))
    [System.IO.File]::WriteAllText($path, $body)
    return $path
  }
}

Describe 'profile.ps1 prompt setup' {

  BeforeEach {
    $script:OriginalHome = $HOME
    $script:CallOrder = @()

    # An empty HOME means .config/powershell/conf.d does not exist,
    # so profile.ps1 skips real conf.d scripts and only its own
    # prompt/zoxide logic runs.
    $homeRoot = (New-Item -ItemType Directory -Path 'TestDrive:\home' -Force).FullName
    Set-Variable -Name HOME -Value $homeRoot -Scope Global -Force

    Set-Item Function:\starship {
      param([Parameter(ValueFromRemainingArguments = $true)][object[]] $Arguments)
      $script:CallOrder += 'starship'
      ''
    }
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force

    foreach ($name in @(
      'starship'
      'zoxide'
      'Test-DotfilesPSReadLineReady'
      'Invoke-Starship-TransientFunction'
      'Enable-TransientPrompt'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'defines the transient-prompt function when the readiness helper reports ready' {
    Set-Item Function:\Test-DotfilesPSReadLineReady { $true }

    . $script:Subject

    Get-Command Invoke-Starship-TransientFunction -ErrorAction SilentlyContinue |
      Should -Not -BeNullOrEmpty
  }

  It 'does not define the transient-prompt function when the readiness helper reports not ready' {
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    . $script:Subject

    Get-Command Invoke-Starship-TransientFunction -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }

  It 'does not define the transient-prompt function when the readiness helper is unavailable and PSReadLine is not loaded' {
    $wasLoaded = $null -ne (Get-Module PSReadLine)
    Remove-Module PSReadLine -ErrorAction SilentlyContinue

    try {
      . $script:Subject

      Get-Command Invoke-Starship-TransientFunction -ErrorAction SilentlyContinue |
        Should -BeNullOrEmpty
    } finally {
      if ($wasLoaded) { Import-Module PSReadLine -ErrorAction SilentlyContinue }
    }
  }

  It 'initializes zoxide after Starship (Starship replaces $function:prompt, so zoxide must hook after)' {
    Set-Item Function:\zoxide {
      param([Parameter(ValueFromRemainingArguments = $true)][object[]] $Arguments)
      $script:CallOrder += 'zoxide'
      ''
    }
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    . $script:Subject

    $script:CallOrder | Should -Be @('starship', 'zoxide')
  }

  It 'skips zoxide initialization when zoxide is not installed' {
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    . $script:Subject

    $script:CallOrder | Should -Be @('starship')
  }

  It 'evaluates the init module from one launch of the resolved starship executable' {
    $starshipLog = Join-Path $TestDrive 'starship-init.log'
    New-Item -ItemType File -Path $starshipLog -Force | Out-Null
    $standIn = New-StarshipStandIn -Dir $TestDrive -LogPath $starshipLog
    $__miseExecutables = @{ starship = $standIn }
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    . $script:Subject

    Get-Content -LiteralPath $starshipLog | Should -Be @('starship init powershell --print-full-init')
    $script:CallOrder | Should -Be @('resolved-init')
  }

  It 'runs the resolved starship for the transient-prompt character when the hook is defined' {
    $starshipLog = Join-Path $TestDrive 'starship-transient.log'
    New-Item -ItemType File -Path $starshipLog -Force | Out-Null
    $standIn = New-StarshipStandIn -Dir $TestDrive -LogPath $starshipLog
    $__miseExecutables = @{ starship = $standIn }
    Set-Item Function:\Test-DotfilesPSReadLineReady { $true }

    . $script:Subject
    $script:CallOrder = @()
    Invoke-Starship-TransientFunction

    Get-Content -LiteralPath $starshipLog | Should -Contain 'starship module character'
    $script:CallOrder | Should -Not -Contain 'starship'
  }

  It 'starts the resolved starship when PATH has no starship command' {
    $starshipLog = Join-Path $TestDrive 'starship-path-less.log'
    New-Item -ItemType File -Path $starshipLog -Force | Out-Null
    $standIn = New-StarshipStandIn -Dir $TestDrive -LogPath $starshipLog
    $__miseExecutables = @{ starship = $standIn }
    Remove-Item Function:\starship -ErrorAction SilentlyContinue
    Set-Item Function:\Test-DotfilesPSReadLineReady { $false }

    . $script:Subject

    Get-Content -LiteralPath $starshipLog | Should -Be @('starship init powershell --print-full-init')
  }
}
