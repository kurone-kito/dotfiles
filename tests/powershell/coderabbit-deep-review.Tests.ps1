# Tests the CodeRabbit review setting (data.coderabbit.review, and the
# deprecated deepReview alias) across the shared review-mode helper, the
# chezmoi configuration template and the generated PowerShell profile. The
# ignore list and the user-global config have their own files:
# chezmoiignore-coderabbit-opt-in.Tests.ps1 and idd-skill-config-tmpl.Tests.ps1.
#
# Every render passes an explicit --config, so the maintainer's own chezmoi
# data can never leak into a test.

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoRoot = (Join-Path $PSScriptRoot '../..' | Resolve-Path).Path
  $script:RepoHome = Join-Path $script:RepoRoot 'home'
  $script:ProfileTemplate = Join-Path $script:RepoHome 'dot_config/powershell/conf.d/25-coderabbit.ps1.tmpl'
  $script:HelperTemplate = Join-Path $script:RepoHome '.chezmoitemplates/coderabbit-review-mode'
  $script:ConfigTemplate = Join-Path $script:RepoRoot '.chezmoi.toml.tmpl'

  # Renders a template with an explicit --config. $CoderabbitJson is the
  # value of data.coderabbit as JSON, or $null to omit it. stderr is split
  # from stdout: the deprecation notice lands on stderr and must never end
  # up in a profile that a test dot-sources. Windows PowerShell 5.1 wraps a
  # native process's stderr lines as ErrorRecord objects, and GitHub
  # Actions' powershell shell steps default $ErrorActionPreference to Stop,
  # so the capture runs in a child scriptblock with 'Continue' (the same fix
  # as signing-resolve.Tests.ps1's Invoke-Render).
  function Invoke-Render {
    param(
      [Parameter(Mandatory)] [string] $TemplatePath,
      [AllowNull()] [string] $CoderabbitJson,
      [switch] $Init,
      [string] $ConfigFormat = 'json'
    )

    $data = if ([string]::IsNullOrEmpty($CoderabbitJson)) { '{}' } else { '{ "coderabbit": ' + $CoderabbitJson + ' }' }
    $configPath = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-config-{0}.json" -f [guid]::NewGuid())
    $destination = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-destination-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    [IO.File]::WriteAllText($configPath, '{ "data": ' + $data + ' }', [Text.UTF8Encoding]::new($false))
    try {
      $raw = & {
        $ErrorActionPreference = 'Continue'
        if ($Init) {
          & chezmoi execute-template --init --file $TemplatePath --config $configPath --config-format json `
            --promptString git.name='Test User' --promptString git.email='test@example.com' `
            --promptString git.signingkey='' --promptString secret.manager='none' `
            --source $script:RepoRoot --destination $destination 2>&1
        } else {
          & chezmoi execute-template --file $TemplatePath --config $configPath --config-format $ConfigFormat `
            --source $script:RepoHome --destination $destination 2>&1
        }
      }
      $exitCode = $LASTEXITCODE
      $errors = @($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
      $lines = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
      $stdout = $lines -join "`n"
      if ($Init) {
        # Drop the trailing comment block: its prose names these keys too.
        $stdout = (@($lines | Where-Object { $_ -notmatch '^#' }) -join "`n")
      }
      [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $stdout
        Stderr   = ($errors | ForEach-Object { $_.ToString() }) -join "`n"
      }
    } finally {
      Remove-Item -LiteralPath $configPath, $destination -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  function Invoke-ProfileWithExternalValue {
    param([string] $ProfileText)
    $profilePath = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-profile-{0}.ps1" -f [guid]::NewGuid())
    $hadOriginalValue = Test-Path Env:CODERABBIT_CRITIQUE_DEEP
    $originalValue = $env:CODERABBIT_CRITIQUE_DEEP
    try {
      [IO.File]::WriteAllText($profilePath, $ProfileText, [Text.UTF8Encoding]::new($false))
      $env:CODERABBIT_CRITIQUE_DEEP = 'external'
      . $profilePath
      $env:CODERABBIT_CRITIQUE_DEEP
    } finally {
      Remove-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
      if ($hadOriginalValue) {
        $env:CODERABBIT_CRITIQUE_DEEP = $originalValue
      } else {
        Remove-Item Env:CODERABBIT_CRITIQUE_DEEP -ErrorAction SilentlyContinue
      }
    }
  }
}

Describe 'CodeRabbit review-mode helper' -Skip:(-not $script:HasChezmoi) {
  It 'resolves <Label> to <Expected>' -ForEach @(
    @{ Label = 'absent'; Json = $null; Expected = 'off'; Notice = $false }
    @{ Label = 'an empty table'; Json = '{}'; Expected = 'off'; Notice = $false }
    @{ Label = 'review false'; Json = '{"review": false}'; Expected = 'off'; Notice = $false }
    @{ Label = 'review true'; Json = '{"review": true}'; Expected = 'lite'; Notice = $false }
    @{ Label = 'review "lite"'; Json = '{"review": "lite"}'; Expected = 'lite'; Notice = $false }
    @{ Label = 'review "deep"'; Json = '{"review": "deep"}'; Expected = 'deep'; Notice = $false }
    @{ Label = 'legacy deepReview true alone'; Json = '{"deepReview": true}'; Expected = 'deep'; Notice = $true }
    @{ Label = 'legacy deepReview false alone'; Json = '{"deepReview": false}'; Expected = 'off'; Notice = $true }
    @{ Label = 'review false with deepReview true'; Json = '{"review": false, "deepReview": true}'; Expected = 'off'; Notice = $true }
    @{ Label = 'review false with deepReview false'; Json = '{"review": false, "deepReview": false}'; Expected = 'off'; Notice = $true }
    @{ Label = 'review true with deepReview true'; Json = '{"review": true, "deepReview": true}'; Expected = 'lite'; Notice = $true }
    @{ Label = 'review true with deepReview false'; Json = '{"review": true, "deepReview": false}'; Expected = 'lite'; Notice = $true }
    @{ Label = 'review "lite" with deepReview true'; Json = '{"review": "lite", "deepReview": true}'; Expected = 'lite'; Notice = $true }
    @{ Label = 'review "lite" with deepReview false'; Json = '{"review": "lite", "deepReview": false}'; Expected = 'lite'; Notice = $true }
    @{ Label = 'review "deep" with deepReview true'; Json = '{"review": "deep", "deepReview": true}'; Expected = 'deep'; Notice = $true }
    @{ Label = 'review "deep" with deepReview false'; Json = '{"review": "deep", "deepReview": false}'; Expected = 'deep'; Notice = $true }
  ) {
    $render = Invoke-Render -TemplatePath $script:HelperTemplate -CoderabbitJson $Json
    $render.ExitCode | Should -Be 0
    $render.Output.Trim() | Should -Be $Expected
    if ($Notice) {
      $render.Stderr | Should -Match 'deepReview is deprecated; use review = "deep"'
      ([regex]::Matches($render.Stderr, 'deprecated')).Count | Should -Be 1
    } else {
      $render.Stderr | Should -BeNullOrEmpty
    }
  }

  It 'fails on <Label> and names <Key>' -ForEach @(
    @{ Label = 'an unknown review string'; Json = '{"review": "bogus"}'; Key = 'data.coderabbit.review'; Allowed = '"lite" or "deep"' }
    @{ Label = 'the string "false"'; Json = '{"review": "false"}'; Key = 'data.coderabbit.review'; Allowed = '"lite" or "deep"' }
    @{ Label = 'a numeric review'; Json = '{"review": 1}'; Key = 'data.coderabbit.review'; Allowed = '"lite" or "deep"' }
    @{ Label = 'an empty review string'; Json = '{"review": ""}'; Key = 'data.coderabbit.review'; Allowed = '"lite" or "deep"' }
    @{ Label = 'an unknown review beside deepReview true'; Json = '{"review": "bogus", "deepReview": true}'; Key = 'data.coderabbit.review'; Allowed = '"lite" or "deep"' }
    @{ Label = 'a string deepReview'; Json = '{"deepReview": "false"}'; Key = 'data.coderabbit.deepReview'; Allowed = 'true or false' }
    @{ Label = 'a numeric deepReview'; Json = '{"deepReview": 1}'; Key = 'data.coderabbit.deepReview'; Allowed = 'true or false' }
    @{ Label = 'a string deepReview beside review "deep"'; Json = '{"review": "deep", "deepReview": "yes"}'; Key = 'data.coderabbit.deepReview'; Allowed = 'true or false' }
    @{ Label = 'a coderabbit value that is not a table'; Json = '"on"'; Key = 'data.coderabbit'; Allowed = 'must be a table' }
  ) {
    $render = Invoke-Render -TemplatePath $script:HelperTemplate -CoderabbitJson $Json
    $render.ExitCode | Should -Not -Be 0
    $render.Stderr | Should -Match ([regex]::Escape($Key))
    $render.Stderr | Should -Match ([regex]::Escape($Allowed))
  }
}

Describe 'CodeRabbit deep-review profile template' -Skip:(-not $script:HasChezmoi) {
  It 'renders one assignment for <Json>' -ForEach @(
    @{ Json = '{"review": "deep"}' }
    @{ Json = '{"deepReview": true}' }
    @{ Json = '{"review": "deep", "deepReview": true}' }
  ) {
    $render = Invoke-Render -TemplatePath $script:ProfileTemplate -CoderabbitJson $Json
    $render.ExitCode | Should -Be 0
    ($render.Output -split "`n" | Where-Object {
      $_ -match '^\$env:CODERABBIT_CRITIQUE_DEEP = ''1''$'
    }).Count | Should -Be 1
  }

  It 'renders no assignment for <Json>' -ForEach @(
    @{ Json = $null }
    @{ Json = '{}' }
    @{ Json = '{"review": false}' }
    @{ Json = '{"review": true}' }
    @{ Json = '{"review": "lite"}' }
    @{ Json = '{"deepReview": false}' }
  ) {
    $render = Invoke-Render -TemplatePath $script:ProfileTemplate -CoderabbitJson $Json
    $render.ExitCode | Should -Be 0
    $render.Output | Should -Not -Match '\$env:CODERABBIT_CRITIQUE_DEEP\s*='
  }

  It 'sets the runtime value to 1 for <Json>' -ForEach @(
    @{ Json = '{"review": "deep"}' }
    @{ Json = '{"deepReview": true}' }
  ) {
    $render = Invoke-Render -TemplatePath $script:ProfileTemplate -CoderabbitJson $Json
    $render.ExitCode | Should -Be 0
    Invoke-ProfileWithExternalValue -ProfileText $render.Output | Should -Be '1'
  }

  It 'preserves an external value for <Json>' -ForEach @(
    @{ Json = $null }
    @{ Json = '{}' }
    @{ Json = '{"review": false}' }
    @{ Json = '{"review": true}' }
    @{ Json = '{"review": "lite"}' }
    @{ Json = '{"deepReview": false}' }
  ) {
    $render = Invoke-Render -TemplatePath $script:ProfileTemplate -CoderabbitJson $Json
    $render.ExitCode | Should -Be 0
    Invoke-ProfileWithExternalValue -ProfileText $render.Output | Should -Be 'external'
  }
}

Describe 'CodeRabbit configuration template' -Skip:(-not $script:HasChezmoi) {
  It 're-emits review as <Line> for <Json>' -ForEach @(
    @{ Json = '{"review": true}'; Line = 'review = true' }
    @{ Json = '{"review": false}'; Line = 'review = false' }
    @{ Json = '{"review": "lite"}'; Line = 'review = "lite"' }
    @{ Json = '{"review": "deep"}'; Line = 'review = "deep"' }
  ) {
    $render = Invoke-Render -TemplatePath $script:ConfigTemplate -CoderabbitJson $Json -Init
    $render.ExitCode | Should -Be 0
    $render.Output | Should -Match '(?m)^\[data\.coderabbit\]$'
    ($render.Output -split "`n") | Should -Contain $Line
    $render.Output | Should -Not -Match 'deepReview'
  }

  It 'emits nothing for an absent or empty coderabbit table, never review = ""' {
    foreach ($json in @($null, '{}')) {
      $render = Invoke-Render -TemplatePath $script:ConfigTemplate -CoderabbitJson $json -Init
      $render.ExitCode | Should -Be 0
      $render.Output | Should -Not -Match '\[data\.coderabbit\]'
      $render.Output | Should -Not -Match '(?m)^review ='
    }
  }

  It 'drops a review that is neither a Boolean nor a string, with a warning' {
    foreach ($json in @('{"review": 1}', '{"review": 1.5}', '{"review": ["deep"]}', '{"review": {"mode": "deep"}}')) {
      $render = Invoke-Render -TemplatePath $script:ConfigTemplate -CoderabbitJson $json -Init
      $render.ExitCode | Should -Be 0
      $render.Output | Should -Not -Match '\[data\.coderabbit\]'
      $render.Stderr | Should -Match 'data\.coderabbit\.review must be true, false.*dropping'
    }
  }

  It 'still emits the legacy deepReview = true and omits it otherwise' {
    $render = Invoke-Render -TemplatePath $script:ConfigTemplate -CoderabbitJson '{"deepReview": true}' -Init
    $render.ExitCode | Should -Be 0
    $render.Output | Should -Match '(?m)^\[data\.coderabbit\]$'
    $render.Output | Should -Match '(?m)^deepReview = true$'
    $render.Output | Should -Not -Match '(?m)^review ='

    foreach ($json in @('{"deepReview": false}', '{"deepReview": "true"}', '{"deepReview": 1}')) {
      $render = Invoke-Render -TemplatePath $script:ConfigTemplate -CoderabbitJson $json -Init
      $render.ExitCode | Should -Be 0
      $render.Output | Should -Not -Match 'deepReview ='
      $render.Output | Should -Not -Match '\[data\.coderabbit\]'
    }
  }

  It 'resolves the emitted configuration to the input mode for <Json>' -ForEach @(
    @{ Json = '{"review": true}' }
    @{ Json = '{"review": false}' }
    @{ Json = '{"review": "lite"}' }
    @{ Json = '{"review": "deep"}' }
    @{ Json = '{"deepReview": true}' }
    @{ Json = '{"review": false, "deepReview": true}' }
  ) {
    $expected = (Invoke-Render -TemplatePath $script:HelperTemplate -CoderabbitJson $Json).Output.Trim()
    $emitted = Invoke-Render -TemplatePath $script:ConfigTemplate -CoderabbitJson $Json -Init
    $emitted.ExitCode | Should -Be 0

    # Parse the emitted TOML the way the next chezmoi apply would.
    $tomlPath = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-emitted-{0}.toml" -f [guid]::NewGuid())
    $destination = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-destination-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    try {
      [IO.File]::WriteAllText($tomlPath, $emitted.Output, [Text.UTF8Encoding]::new($false))
      $raw = & {
        $ErrorActionPreference = 'Continue'
        & chezmoi execute-template --file $script:HelperTemplate --config $tomlPath --config-format toml `
          --source $script:RepoHome --destination $destination 2>&1
      }
      $LASTEXITCODE | Should -Be 0
      (@($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n").Trim() |
        Should -Be $expected
    } finally {
      Remove-Item -LiteralPath $tomlPath, $destination -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
