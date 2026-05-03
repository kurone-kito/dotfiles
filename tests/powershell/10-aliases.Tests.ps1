# Tests for the PowerShell aliases configuration script.
# Exercises: base aliases, compatibility aliases, and skip behavior.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '10-aliases.ps1'
}

Describe '10-aliases' {

  BeforeEach {
    $script:OriginalLl = Get-Alias -Name ll -ErrorAction SilentlyContinue
    $script:OriginalWhich = Get-Alias -Name which -ErrorAction SilentlyContinue
    $script:OriginalWt = Get-Alias -Name wt -ErrorAction SilentlyContinue
    $script:OriginalGitWt = Get-Alias -Name git-wt -ErrorAction SilentlyContinue
    $script:OriginalBat = Get-Alias -Name bat -ErrorAction SilentlyContinue
    $script:OriginalBatcat = Get-Alias -Name batcat -ErrorAction SilentlyContinue
    Remove-Item Alias:\ll -ErrorAction SilentlyContinue
    Remove-Item Alias:\which -ErrorAction SilentlyContinue
    Remove-Item Alias:\wt -ErrorAction SilentlyContinue
    Remove-Item Alias:\git-wt -ErrorAction SilentlyContinue
    Remove-Item Alias:\bat -ErrorAction SilentlyContinue
    Remove-Item Alias:\batcat -ErrorAction SilentlyContinue

    Mock Get-Command { $null } -ParameterFilter {
      $Name -in @('wt', 'git-wt', 'bat', 'batcat')
    }
  }

  AfterEach {
    Remove-Item Alias:\ll -ErrorAction SilentlyContinue
    Remove-Item Alias:\which -ErrorAction SilentlyContinue
    Remove-Item Alias:\wt -ErrorAction SilentlyContinue
    Remove-Item Alias:\git-wt -ErrorAction SilentlyContinue
    Remove-Item Alias:\bat -ErrorAction SilentlyContinue
    Remove-Item Alias:\batcat -ErrorAction SilentlyContinue
    if ($script:OriginalLl) {
      Set-Alias -Name ll -Value $script:OriginalLl.Definition -Scope Global
    }
    if ($script:OriginalWhich) {
      Set-Alias -Name which -Value $script:OriginalWhich.Definition -Scope Global
    }
    if ($script:OriginalWt) {
      Set-Alias -Name wt -Value $script:OriginalWt.Definition -Scope Global
    }
    if ($script:OriginalGitWt) {
      Set-Alias -Name git-wt -Value $script:OriginalGitWt.Definition -Scope Global
    }
    if ($script:OriginalBat) {
      Set-Alias -Name bat -Value $script:OriginalBat.Definition -Scope Global
    }
    if ($script:OriginalBatcat) {
      Set-Alias -Name batcat -Value $script:OriginalBatcat.Definition -Scope Global
    }
  }

  It 'creates the ll alias pointing to Get-ChildItem' {
    . $script:Subject

    $alias = Get-Alias -Name ll -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.ReferencedCommand.Name | Should -Be 'Get-ChildItem'
  }

  It 'creates the which alias pointing to Get-Command' {
    . $script:Subject

    $alias = Get-Alias -Name which -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.ReferencedCommand.Name | Should -Be 'Get-Command'
  }

  It 'creates the wt alias pointing to git-wt when git-wt is available' {
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application' }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $alias = Get-Alias -Name wt -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.Definition | Should -Be 'git-wt'
  }

  It 'skips the wt alias when wt already exists' {
    Mock Get-Command {
      [pscustomobject]@{ Name = 'wt'; CommandType = 'Application' }
    } -ParameterFilter { $Name -eq 'wt' }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application' }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    Get-Alias -Name wt -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
  }

  It 'creates the git-wt alias pointing to wt when wt is available' {
    Mock Get-Command {
      [pscustomobject]@{ Name = 'wt'; CommandType = 'Application' }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $alias = Get-Alias -Name git-wt -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.Definition | Should -Be 'wt'
  }

  It 'skips the git-wt alias when wt resolves to Windows Terminal' {
    Mock Get-Command {
      [pscustomobject]@{
        Name = 'wt'
        CommandType = 'Application'
        Path = 'C:\Users\me\AppData\Local\Microsoft\WindowsApps\wt.exe'
      }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    Get-Alias -Name git-wt -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
  }

  It 'skips the git-wt alias when wt resolves to Microsoft.WindowsTerminal path' {
    Mock Get-Command {
      [pscustomobject]@{
        Name = 'wt'
        CommandType = 'Application'
        Path = 'C:\Program Files\WindowsApps\Microsoft.WindowsTerminal_1.21.10.0_x64__8wekyb3d8bbwe\wt.exe'
      }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    Get-Alias -Name git-wt -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
  }

  It 'skips the git-wt alias when first wt is Windows Terminal even with worktrunk wt later in PATH' {
    Mock Get-Command {
      @(
        [pscustomobject]@{
          Name = 'wt'; CommandType = 'Application'
          Path = 'C:\Users\me\AppData\Local\Microsoft\WindowsApps\wt.exe'
        },
        [pscustomobject]@{
          Name = 'wt'; CommandType = 'Application'
          Path = 'C:\tools\worktrunk\wt.exe'
        }
      )
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    Get-Alias -Name git-wt -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
  }

  It 'creates the batcat alias pointing to bat when bat is available' {
    Mock Get-Command {
      [pscustomobject]@{ Name = 'bat'; CommandType = 'Application' }
    } -ParameterFilter { $Name -eq 'bat' }

    . $script:Subject

    $alias = Get-Alias -Name batcat -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.Definition | Should -Be 'bat'
  }

  It 'creates the bat alias pointing to batcat when batcat is available' {
    Mock Get-Command {
      [pscustomobject]@{ Name = 'batcat'; CommandType = 'Application' }
    } -ParameterFilter { $Name -eq 'batcat' }

    . $script:Subject

    $alias = Get-Alias -Name bat -ErrorAction SilentlyContinue
    $alias | Should -Not -BeNullOrEmpty
    $alias.Definition | Should -Be 'batcat'
  }

  It 'skips the bat alias when bat already exists' {
    Mock Get-Command {
      [pscustomobject]@{ Name = 'bat'; CommandType = 'Application' }
    } -ParameterFilter { $Name -eq 'bat' }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'batcat'; CommandType = 'Application' }
    } -ParameterFilter { $Name -eq 'batcat' }

    . $script:Subject

    Get-Alias -Name bat -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
  }
}
