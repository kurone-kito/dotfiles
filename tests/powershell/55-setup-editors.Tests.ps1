# Tests for the editor setup chezmoi post-apply script (PowerShell version).
# Uses the pre-rendered fixture instead of the chezmoi template.

BeforeAll {
  $script:Fixture = Join-Path $PSScriptRoot 'fixtures/55-setup-editors.ps1'
}

Describe 'setup-editors' {
  BeforeEach {
    $script:OrigHome = $env:HOME
    $script:OrigXdg = $env:XDG_DATA_HOME
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) `
      "setup-editors-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    $env:HOME = $script:TempDir
  }

  AfterEach {
    $env:HOME = $script:OrigHome
    if ($null -eq $script:OrigXdg) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue }
    else { $env:XDG_DATA_HOME = $script:OrigXdg }
    if (Test-Path $script:TempDir) {
      Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Context 'when neither editor is installed' {
    It 'prints no-editors-found message' {
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'vim' }
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'nvim' }
      Mock Get-Command { $null } -ParameterFilter { $Name -eq 'curl' }

      $output = & pwsh -NoProfile -Command "
        function Get-Command { param([string]`$Name, [string]`$ErrorAction) `$null }
        `$env:HOME = '$($script:TempDir -replace "'","''")'
        & '$($script:Fixture -replace "'","''")'
      " 2>&1

      ($output | Out-String) | Should -BeLike '*No editors found*'
    }
  }

  Context 'vim plugin setup' {
    It 'reports vim not found when vim is absent' {
      $output = & pwsh -NoProfile -Command "
        function Get-Command {
          param([string]`$Name, [string]`$ErrorAction)
          `$null
        }
        `$env:HOME = '$($script:TempDir -replace "'","''")'
        & '$($script:Fixture -replace "'","''")'
      " 2>&1

      ($output | Out-String) | Should -BeLike '*vim not found*'
    }

    It 'reports nvim not found when nvim is absent' {
      $output = & pwsh -NoProfile -Command "
        function Get-Command {
          param([string]`$Name, [string]`$ErrorAction)
          `$null
        }
        `$env:HOME = '$($script:TempDir -replace "'","''")'
        & '$($script:Fixture -replace "'","''")'
      " 2>&1

      ($output | Out-String) | Should -BeLike '*nvim not found*'
    }

    It 'skips vim-plug bootstrap when plug.vim exists' {
      # Pre-create plug.vim so bootstrap is skipped
      $vimDir = Join-Path $script:TempDir '.vim/autoload'
      New-Item -ItemType Directory -Path $vimDir -Force | Out-Null
      Set-Content (Join-Path $vimDir 'plug.vim') ''

      $output = & pwsh -NoProfile -Command "
        function script:OrigGetCommand {}
        `$getRealCommand = (Get-Command Get-Command).ScriptBlock
        function Get-Command {
          param([string]`$Name, [string]`$ErrorAction)
          if (`$Name -eq 'vim') {
            [pscustomobject]@{ Name = 'vim'; Source = '/mock/vim' }
          } elseif (`$Name -eq 'nvim') {
            `$null
          } else {
            & `$using:getRealCommand -Name `$Name -ErrorAction SilentlyContinue
          }
        }
        function vim { Write-Host 'vim:mock' }
        `$env:HOME = '$($script:TempDir -replace "'","''")'
        & '$($script:Fixture -replace "'","''")'
      " 2>&1

      $text = $output | Out-String
      $text | Should -BeLike '*vim plugin sync complete*'
      $text | Should -Not -BeLike '*Bootstrapping vim-plug*'
    }
  }

  Context 'nvim lazy.nvim sync' {
    It 'runs nvim headless sync when nvim is available' {
      # XDG_DATA_HOME directs lazydir under the temp tree so the mock
      # nvim creates it where the fixture will check.
      $xdgData = Join-Path $script:TempDir (Join-Path '.local' 'share')
      $output = & pwsh -NoProfile -Command "
        function Get-Command {
          param([string]`$Name, [string]`$ErrorAction)
          if (`$Name -eq 'nvim') {
            [pscustomobject]@{ Name = 'nvim'; Source = '/mock/nvim' }
          } else { `$null }
        }
        function nvim {
          `$xdg = if (`$env:XDG_DATA_HOME) { `$env:XDG_DATA_HOME } else {
            Join-Path `$env:HOME (Join-Path '.local' 'share')
          }
          `$lazydir = Join-Path `$xdg (Join-Path 'nvim' (Join-Path 'lazy' 'lazy.nvim'))
          if (-not (Test-Path `$lazydir)) {
            New-Item -ItemType Directory -Path `$lazydir -Force | Out-Null
          }
          Write-Host ('nvim-args:' + (`$args -join ' '))
        }
        `$env:HOME = '$($script:TempDir -replace "'","''")'
        `$env:XDG_DATA_HOME = '$($xdgData -replace "'","''")'
        & '$($script:Fixture -replace "'","''")'
      " 2>&1

      $text = $output | Out-String
      $text | Should -BeLike '*nvim plugin sync complete*'
      $text | Should -BeLike '*nvim-args:--headless*Lazy*sync*'
    }

    It 'warns when lazy.nvim bootstrap fails' {
      # XDG_DATA_HOME directs the lazydir check under temp tree where
      # the mock nvim will NOT create it, triggering the warning.
      $xdgData = Join-Path $script:TempDir (Join-Path '.local' 'share')
      $output = & pwsh -NoProfile -Command "
        function Get-Command {
          param([string]`$Name, [string]`$ErrorAction)
          if (`$Name -eq 'nvim') {
            [pscustomobject]@{ Name = 'nvim'; Source = '/mock/nvim' }
          } else { `$null }
        }
        function nvim { `$global:LASTEXITCODE = 1 }
        `$env:HOME = '$($script:TempDir -replace "'","''")'
        `$env:XDG_DATA_HOME = '$($xdgData -replace "'","''")'
        & '$($script:Fixture -replace "'","''")'
      " 2>&1

      $text = $output | Out-String
      $text | Should -BeLike '*lazy.nvim bootstrap failed*'
    }
  }
}
