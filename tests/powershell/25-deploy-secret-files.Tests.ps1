BeforeAll {
  $script:Fixture = Join-Path (Join-Path $PSScriptRoot 'fixtures') '25-deploy-secret-files.ps1'
  $script:Template = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home') `
    'run_onchange_after_25-deploy-secret-files.ps1.tmpl'
  $script:TemplateContent = Get-Content -Raw $script:Template
}

Describe '25-deploy-secret-files template' {
  Context 'static checks' {
    It 'skips when manager is none' {
      $script:TemplateContent | Should -Match 'eq \$manager "none"'
    }

    It 'validates target has no path traversal' {
      $script:TemplateContent | Should -Match 'contains "\.\."'
    }

    It 'validates target is not absolute' {
      $script:TemplateContent | Should -Match 'hasPrefix "/"'
    }

    It 'restricts file permissions with icacls' {
      $script:TemplateContent | Should -Match 'icacls'
    }

    It 'secures parent directory permissions' {
      $script:TemplateContent | Should -Match 'icacls \$targetDir'
    }

    It 'wires Record-State for each secret file write' {
      $script:TemplateContent | Should -Match "Record-State -Category 'secretFile'"
    }

    It 'guards Record-State when the helper is absent' {
      $script:TemplateContent | Should -Match 'if \(-not \(Test-Path \$deployState\)\) \{ return \}'
    }
  }

  Context 'fixture deployment' -Skip:($IsWindows -eq $false) {
    BeforeEach {
      $env:DOTFILES_TEST_HOME = Join-Path $TestDrive 'home'
      New-Item -ItemType Directory -Path $env:DOTFILES_TEST_HOME -Force | Out-Null
    }

    AfterEach {
      $env:DOTFILES_TEST_HOME = $null
    }

    It 'deploys .aws/credentials with correct content' {
      & $script:Fixture
      $path = Join-Path (Join-Path $env:DOTFILES_TEST_HOME '.aws') 'credentials'
      $path | Should -Exist
      $content = Get-Content -Raw $path
      $content | Should -Match 'aws_access_key_id = AKIAEXAMPLE'
    }

    It 'deploys .docker/config.json with correct content' {
      & $script:Fixture
      $path = Join-Path (Join-Path $env:DOTFILES_TEST_HOME '.docker') 'config.json'
      $path | Should -Exist
      $content = Get-Content -Raw $path
      $content | Should -Match '"auths"'
    }

    It 'outputs deployment status for each entry' {
      $output = & $script:Fixture 6>&1 | Out-String
      $output | Should -Match '==> aws-credentials:'
      $output | Should -Match '==> docker-auth:'
      $output | Should -Match 'secret file deploy complete\.'
    }
  }
}
