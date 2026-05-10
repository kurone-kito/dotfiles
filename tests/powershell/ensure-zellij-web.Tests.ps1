# Tests for the Zellij Web ensure script.
# Exercises: command lookup, fallback resolution, idempotent start flow,
# and optional Tailscale Serve publication.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot 'fixtures/ensure-zellij-web.ps1'
}

Describe 'ensure-zellij-web' {

  BeforeEach {
    $script:OriginalSkipInit = $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_INIT
    $script:OriginalLocalAppData = $env:LOCALAPPDATA
    $script:OriginalProgramFiles = $env:ProgramFiles
    $script:OriginalProgramFilesX86 = ${env:ProgramFiles(x86)}
    $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_INIT = '1'
    . $script:Subject
    $script:DotfilesZellijWebBind = '127.0.0.1'
    $script:DotfilesZellijWebPort = 8082
    $script:DotfilesZellijWebBaseUrl = ''
    $script:DotfilesZellijWebTailscaleEnabled = $false
    $script:DotfilesZellijWebTailscaleHttpsPort = 443
  }

  AfterEach {
    $env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_INIT = $script:OriginalSkipInit
    $env:LOCALAPPDATA = $script:OriginalLocalAppData
    $env:ProgramFiles = $script:OriginalProgramFiles
    ${env:ProgramFiles(x86)} = $script:OriginalProgramFilesX86

    foreach ($name in @(
      'Get-DotfilesZellijCommand'
      'Get-DotfilesTailscaleCommand'
      'Get-DotfilesZellijWebServePath'
      'Get-DotfilesZellijWebServeTarget'
      'Assert-DotfilesZellijWebTailscaleSettings'
      'Get-DotfilesTailscaleServeStatusJson'
      'Test-DotfilesZellijWebRunning'
      'Test-DotfilesZellijWebTailscaleServeConfigured'
      'Start-DotfilesZellijWeb'
      'Set-DotfilesZellijWebTailscaleServe'
      'Ensure-DotfilesZellijWebPublication'
      'Ensure-DotfilesZellijWeb'
    )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  It 'prefers the zellij command from PATH' {
    Mock Get-Command {
      [pscustomobject]@{ Path = 'TestDrive:\zellij.exe' }
    } -ParameterFilter { $Name -eq 'zellij' }

    Get-DotfilesZellijCommand | Should -Be 'TestDrive:\zellij.exe'
  }

  It 'falls back to the WinGet-installed zellij path when PATH lookup fails' {
    $env:LOCALAPPDATA = 'TestDrive:\LocalAppData'
    $fallback = Join-Path $env:LOCALAPPDATA 'Zellij\zellij.exe'
    New-Item -ItemType Directory -Path (Split-Path $fallback) -Force | Out-Null
    New-Item -ItemType File -Path $fallback -Force | Out-Null

    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'zellij' }

    Get-DotfilesZellijCommand | Should -Be $fallback
  }

  It 'falls back to the Program Files tailscale path when PATH lookup fails' {
    $env:ProgramFiles = 'TestDrive:\ProgramFiles'
    ${env:ProgramFiles(x86)} = ''
    $fallback = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    New-Item -ItemType Directory -Path (Split-Path $fallback) -Force | Out-Null
    New-Item -ItemType File -Path $fallback -Force | Out-Null

    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'tailscale' }

    Get-DotfilesTailscaleCommand | Should -Be $fallback
  }

  It 'does not start zellij web when it is already running' {
    Set-Item Function:\Get-DotfilesZellijCommand {
      'TestDrive:\zellij.exe'
    }
    Set-Item Function:\Test-DotfilesZellijWebRunning {
      param([string]$ZellijCommand)
      $true
    }
    Set-Item Function:\Start-DotfilesZellijWeb {
      throw 'should not start'
    }

    Ensure-DotfilesZellijWeb | Should -BeFalse
  }

  It 'starts zellij web when it is offline and verifies health afterwards' {
    $script:StatusChecks = 0
    $script:StartCalls = 0

    Set-Item Function:\Get-DotfilesZellijCommand {
      'TestDrive:\zellij.exe'
    }
    Set-Item Function:\Test-DotfilesZellijWebRunning {
      param([string]$ZellijCommand)
      $script:StatusChecks++
      return ($script:StatusChecks -ge 2)
    }
    Set-Item Function:\Start-DotfilesZellijWeb {
      param([string]$ZellijCommand)
      $script:StartCalls++
    }

    Ensure-DotfilesZellijWeb | Should -BeTrue
    $script:StartCalls | Should -Be 1
    $script:StatusChecks | Should -Be 2
  }

  It 'normalizes a non-root base_url into the tailscale serve path' {
    $script:DotfilesZellijWebBaseUrl = 'zellij'

    Get-DotfilesZellijWebServePath | Should -Be '/zellij'
  }

  It 'configures tailscale serve when enabled and the route is missing' {
    $script:DotfilesZellijWebTailscaleEnabled = $true
    $script:StatusChecks = 0
    $script:ServeStatusChecks = 0
    $script:ConfiguredTailscaleCommand = $null

    Set-Item Function:\Get-DotfilesZellijCommand {
      'TestDrive:\zellij.exe'
    }
    Set-Item Function:\Test-DotfilesZellijWebRunning {
      param([string] $ZellijCommand)
      $script:StatusChecks++
      return ($script:StatusChecks -ge 2)
    }
    Set-Item Function:\Start-DotfilesZellijWeb {
      param([string] $ZellijCommand)
    }
    Set-Item Function:\Get-DotfilesTailscaleCommand {
      'TestDrive:\tailscale.exe'
    }
    Set-Item Function:\Get-DotfilesTailscaleServeStatusJson {
      param([string] $TailscaleCommand)
      $script:ServeStatusChecks++
      if ($script:ServeStatusChecks -eq 1) {
        return '{}'
      }

      return @'
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "node:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://127.0.0.1:8082"
        }
      }
    }
  }
}
'@
    }
    Set-Item Function:\Set-DotfilesZellijWebTailscaleServe {
      param([string] $TailscaleCommand)
      $script:ConfiguredTailscaleCommand = $TailscaleCommand
    }

    Ensure-DotfilesZellijWeb | Should -BeTrue
    $script:ConfiguredTailscaleCommand | Should -Be 'TestDrive:\tailscale.exe'
    $script:ServeStatusChecks | Should -Be 2
  }

  It 'does not reconfigure tailscale serve when the desired route already exists' {
    $script:DotfilesZellijWebTailscaleEnabled = $true

    Set-Item Function:\Get-DotfilesZellijCommand {
      'TestDrive:\zellij.exe'
    }
    Set-Item Function:\Test-DotfilesZellijWebRunning {
      param([string] $ZellijCommand)
      $true
    }
    Set-Item Function:\Get-DotfilesTailscaleCommand {
      'TestDrive:\tailscale.exe'
    }
    Set-Item Function:\Get-DotfilesTailscaleServeStatusJson {
      param([string] $TailscaleCommand)
      @'
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "node:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://127.0.0.1:8082"
        }
      }
    }
  }
}
'@
    }
    Mock Set-DotfilesZellijWebTailscaleServe { }

    Ensure-DotfilesZellijWeb | Should -BeFalse
    Assert-MockCalled Set-DotfilesZellijWebTailscaleServe -Times 0
  }

  It 'rejects tailscale publication when zellij bind is not loopback' {
    $script:DotfilesZellijWebTailscaleEnabled = $true
    $script:DotfilesZellijWebBind = '0.0.0.0'

    Set-Item Function:\Get-DotfilesZellijCommand {
      'TestDrive:\zellij.exe'
    }
    Set-Item Function:\Test-DotfilesZellijWebRunning {
      param([string] $ZellijCommand)
      $true
    }

    { Ensure-DotfilesZellijWeb } |
      Should -Throw 'zellij.web.tailscale.enabled requires zellij.web.bind to remain 127.0.0.1.'
  }
}
