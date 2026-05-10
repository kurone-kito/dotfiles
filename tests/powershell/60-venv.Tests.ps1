# Tests for the PowerShell Python venv activation helper script.
# Exercises: alias creation, active-venv guard, directory search order,
# fallback warning.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '60-venv.ps1'
}

Describe '60-venv' {

  BeforeEach {
    $script:OriginalVirtualEnv = $env:VIRTUAL_ENV
    $env:VIRTUAL_ENV = $null
    $global:VenvTestActivated = $null
    Remove-Item Function:\Invoke-VenvActivate -ErrorAction SilentlyContinue
    Remove-Item Alias:\venv-activate -ErrorAction SilentlyContinue
    Push-Location TestDrive:\
  }

  AfterEach {
    Pop-Location
    $env:VIRTUAL_ENV = $script:OriginalVirtualEnv
    $global:VenvTestActivated = $null
    Remove-Item Function:\Invoke-VenvActivate -ErrorAction SilentlyContinue
    Remove-Item Alias:\venv-activate -ErrorAction SilentlyContinue
  }

  It 'creates the venv-activate alias pointing to Invoke-VenvActivate' {
    . $script:Subject

    $alias = Get-Alias -Name venv-activate -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.ReferencedCommand.Name | Should -Be 'Invoke-VenvActivate'
  }

  It 'warns and returns early when VIRTUAL_ENV is already set' {
    . $script:Subject

    $env:VIRTUAL_ENV = 'C:\some\venv'

    $result = Invoke-VenvActivate 3>&1
    $result | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
      Select-Object -ExpandProperty Message |
      Should -BeLike '*Already in venv*'
  }

  It 'activates .venv\Scripts\Activate.ps1 when it exists' {
    $activatePath = Join-Path TestDrive:\ '.venv\Scripts\Activate.ps1'
    New-Item -ItemType Directory -Path (Split-Path $activatePath) -Force | Out-Null
    Set-Content -Path $activatePath -Value '$global:VenvTestActivated = ".venv/Scripts"'

    . $script:Subject
    Invoke-VenvActivate

    $global:VenvTestActivated | Should -Be '.venv/Scripts'
  }

  It 'falls back to venv\bin\Activate.ps1 when .venv is not present' {
    Remove-Item -Recurse -Force (Join-Path TestDrive:\ '.venv') -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path TestDrive:\ 'venv') -ErrorAction SilentlyContinue

    $activatePath = Join-Path TestDrive:\ 'venv\bin\Activate.ps1'
    New-Item -ItemType Directory -Path (Split-Path $activatePath) -Force | Out-Null
    Set-Content -Path $activatePath -Value '$global:VenvTestActivated = "venv/bin"'

    . $script:Subject
    Invoke-VenvActivate

    $global:VenvTestActivated | Should -Be 'venv/bin'
  }

  It 'writes a warning when no venv directory is found' {
    Remove-Item -Recurse -Force (Join-Path TestDrive:\ '.venv') -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path TestDrive:\ 'venv') -ErrorAction SilentlyContinue

    . $script:Subject

    $result = Invoke-VenvActivate 3>&1
    "$result" | Should -BeLike '*No .venv or venv*'
  }

  It 'checks .venv before venv (precedence order)' {
    $dotVenvPath = Join-Path TestDrive:\ '.venv\Scripts\Activate.ps1'
    $venvPath = Join-Path TestDrive:\ 'venv\Scripts\Activate.ps1'

    New-Item -ItemType Directory -Path (Split-Path $dotVenvPath) -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path $venvPath) -Force | Out-Null
    Set-Content -Path $dotVenvPath -Value '$global:VenvTestActivated = ".venv"'
    Set-Content -Path $venvPath -Value '$global:VenvTestActivated = "venv"'

    . $script:Subject
    Invoke-VenvActivate

    $global:VenvTestActivated | Should -Be '.venv'
  }
}
