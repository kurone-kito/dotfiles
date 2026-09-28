# Tests the optional CodeRabbit deep-review setting across the chezmoi
# configuration template and the generated PowerShell profile.

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoRoot = (Join-Path $PSScriptRoot '../..' | Resolve-Path).Path
  $script:TemplatePath = Join-Path $script:RepoRoot 'home/dot_config/powershell/conf.d/25-coderabbit.ps1.tmpl'

  function Invoke-Render {
    param(
      [AllowNull()]
      [Nullable[bool]] $DeepReview
    )

    $config = @{ data = @{} }
    if ($null -ne $DeepReview) {
      $config.data.coderabbit = @{ deepReview = [bool]$DeepReview }
    }
    $configPath = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-config-{0}.json" -f [guid]::NewGuid())
    $destination = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-destination-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $configJson = $config | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($configPath, $configJson, [Text.UTF8Encoding]::new($false))
    try {
      $output = & chezmoi execute-template --file $script:TemplatePath --config $configPath --config-format json --source (Join-Path $script:RepoRoot 'home') --destination $destination 2>&1
      [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output -join [Environment]::NewLine)
      }
    } finally {
      Remove-Item -LiteralPath $configPath, $destination -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe 'CodeRabbit deep-review profile template' -Skip:(-not $script:HasChezmoi) {
  It 'renders one assignment when enabled' {
    $render = Invoke-Render -DeepReview $true
    $render.ExitCode | Should -Be 0
    ($render.Output -split [Environment]::NewLine | Where-Object {
      $_ -match '^\$env:CODERABBIT_CRITIQUE_DEEP = ''1''$'
    }).Count | Should -Be 1
  }

  It 'renders no assignment when disabled or absent' {
    foreach ($value in @($false, $null)) {
      $render = Invoke-Render -DeepReview $value
      $render.ExitCode | Should -Be 0
      $render.Output | Should -Not -Match '\$env:CODERABBIT_CRITIQUE_DEEP\s*='
    }
  }

  It 'sets the runtime value to 1 when enabled' {
    $render = Invoke-Render -DeepReview $true
    $render.ExitCode | Should -Be 0
    $profile = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-profile-{0}.ps1" -f [guid]::NewGuid())
    $hadOriginalValue = Test-Path Env:CODERABBIT_CRITIQUE_DEEP
    $originalValue = $env:CODERABBIT_CRITIQUE_DEEP
    try {
      [IO.File]::WriteAllText($profile, $render.Output, [Text.UTF8Encoding]::new($false))
      $env:CODERABBIT_CRITIQUE_DEEP = 'external'
      . $profile
      $env:CODERABBIT_CRITIQUE_DEEP | Should -Be '1'
    } finally {
      Remove-Item -LiteralPath $profile -Force -ErrorAction SilentlyContinue
      if ($hadOriginalValue) {
        $env:CODERABBIT_CRITIQUE_DEEP = $originalValue
      } else {
        Remove-Item Env:CODERABBIT_CRITIQUE_DEEP -ErrorAction SilentlyContinue
      }
    }
  }

  It 'preserves an external value when disabled or absent' {
    foreach ($value in @($false, $null)) {
      $render = Invoke-Render -DeepReview $value
      $render.ExitCode | Should -Be 0
      $profile = Join-Path ([IO.Path]::GetTempPath()) ("coderabbit-profile-{0}.ps1" -f [guid]::NewGuid())
      $hadOriginalValue = Test-Path Env:CODERABBIT_CRITIQUE_DEEP
      $originalValue = $env:CODERABBIT_CRITIQUE_DEEP
      try {
        [IO.File]::WriteAllText($profile, $render.Output, [Text.UTF8Encoding]::new($false))
        $env:CODERABBIT_CRITIQUE_DEEP = 'external'
        . $profile
        $env:CODERABBIT_CRITIQUE_DEEP | Should -Be 'external'
      } finally {
        Remove-Item -LiteralPath $profile -Force -ErrorAction SilentlyContinue
        if ($hadOriginalValue) {
          $env:CODERABBIT_CRITIQUE_DEEP = $originalValue
        } else {
          Remove-Item Env:CODERABBIT_CRITIQUE_DEEP -ErrorAction SilentlyContinue
        }
      }
    }
  }
}
