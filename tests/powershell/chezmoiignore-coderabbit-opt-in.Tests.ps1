# The CodeRabbit critique launchers are opt-in: home/.chezmoiignore.tmpl
# lists them as ignored when data.coderabbit.review resolves to "off" (the
# default) and deploys them for "lite" and "deep". Renders the real ignore
# list for both Linux and Windows by overriding chezmoi.os, mirroring
# tests/bash/chezmoiignore-coderabbit-opt-in.bats.
#
# Every render passes an explicit --config, so the maintainer's own chezmoi
# data can never leak into a test, and --override-data-file only for
# chezmoi.os (an extensionless override-data file is rejected, and Windows
# PowerShell 5.1 mangles inline JSON arguments).

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoHome = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home' | Resolve-Path
  $script:IgnoreTemplate = Join-Path $script:RepoHome '.chezmoiignore.tmpl'

  # $CoderabbitJson: the value of data.coderabbit as JSON, or empty to omit it.
  function Invoke-IgnoreRender {
    param(
      [Parameter(Mandatory)] [string] $Os,
      [string] $CoderabbitJson
    )
    $data = if ([string]::IsNullOrEmpty($CoderabbitJson)) { '{}' } else { '{ "coderabbit": ' + $CoderabbitJson + ' }' }
    $configFile = Join-Path ([IO.Path]::GetTempPath()) ("ignore-config-{0}.json" -f [guid]::NewGuid())
    $overrideFile = Join-Path ([IO.Path]::GetTempPath()) ("ignore-override-{0}.json" -f [guid]::NewGuid())
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("ignore-dest-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    [IO.File]::WriteAllText($configFile, '{ "data": ' + $data + ' }', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($overrideFile, "{`"chezmoi`":{`"os`":`"$Os`"}}", [Text.UTF8Encoding]::new($false))
    try {
      $raw = & {
        $ErrorActionPreference = 'Continue'
        & chezmoi execute-template --file $script:IgnoreTemplate `
          --config $configFile --config-format json `
          --override-data-file $overrideFile `
          --source $script:RepoHome --destination $dest 2>&1
      }
      $exitCode = $LASTEXITCODE
      $errors = @($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
      $lines = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
          ForEach-Object { "$_".Trim() } | Where-Object { $_ })
      [pscustomobject]@{
        ExitCode = $exitCode
        Lines    = $lines
        Stderr   = ($errors | ForEach-Object { $_.ToString() }) -join "`n"
      }
    } finally {
      Remove-Item -LiteralPath $configFile, $overrideFile, $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe 'CodeRabbit launcher opt-in in .chezmoiignore.tmpl' -Skip:(-not $script:HasChezmoi) {
  Context 'review off' {
    It 'ignores every CodeRabbit launcher exactly once on <Os> for <Json>' -ForEach @(
      @{ Os = 'linux'; Json = '' }
      @{ Os = 'linux'; Json = '{}' }
      @{ Os = 'linux'; Json = '{"review": false}' }
      @{ Os = 'linux'; Json = '{"deepReview": false}' }
      @{ Os = 'windows'; Json = '' }
      @{ Os = 'windows'; Json = '{}' }
      @{ Os = 'windows'; Json = '{"review": false}' }
      @{ Os = 'windows'; Json = '{"deepReview": false}' }
    ) {
      $render = Invoke-IgnoreRender -Os $Os -CoderabbitJson $Json
      $render.ExitCode | Should -Be 0
      foreach ($entry in '.local/bin/coderabbit-critique', '.local/bin/coderabbit-critique.ps1', '.local/bin/coderabbit-critique.cmd') {
        @($render.Lines | Where-Object { $_ -ceq $entry }).Count | Should -Be 1
      }
    }
  }

  Context 'review lite, deep and the legacy alias' {
    It 'deploys the launchers on Windows for <Json>' -ForEach @(
      @{ Json = '{"review": true}' }
      @{ Json = '{"review": "lite"}' }
      @{ Json = '{"review": "deep"}' }
      @{ Json = '{"deepReview": true}' }
    ) {
      $render = Invoke-IgnoreRender -Os 'windows' -CoderabbitJson $Json
      $render.ExitCode | Should -Be 0
      @($render.Lines | Where-Object { $_ -match 'coderabbit-critique' }).Count | Should -Be 0
    }

    It 'ignores only the Windows .cmd twin on Linux for <Json>' -ForEach @(
      @{ Json = '{"review": true}' }
      @{ Json = '{"review": "lite"}' }
      @{ Json = '{"review": "deep"}' }
      @{ Json = '{"deepReview": true}' }
    ) {
      $render = Invoke-IgnoreRender -Os 'linux' -CoderabbitJson $Json
      $render.ExitCode | Should -Be 0
      @($render.Lines | Where-Object { $_ -match 'coderabbit-critique' }) | Should -Be @('.local/bin/coderabbit-critique.cmd')
    }
  }

  Context 'everything else in the ignore list' {
    It 'keeps the idd-critique-telemetry launchers and every other entry the same in every mode on <Os>' -ForEach @(
      @{ Os = 'linux' }
      @{ Os = 'windows' }
    ) {
      $off = Invoke-IgnoreRender -Os $Os -CoderabbitJson '{"review": false}'
      $off.ExitCode | Should -Be 0
      $offRest = @($off.Lines | Where-Object { $_ -notmatch 'coderabbit-critique' })
      foreach ($json in '{"review": "lite"}', '{"review": "deep"}') {
        $other = Invoke-IgnoreRender -Os $Os -CoderabbitJson $json
        $other.ExitCode | Should -Be 0
        @($other.Lines | Where-Object { $_ -notmatch 'coderabbit-critique' }) | Should -Be $offRest
      }
    }

    It 'lists the two idd-critique-telemetry .cmd launchers on Linux' {
      $render = Invoke-IgnoreRender -Os 'linux'
      $render.Lines | Should -Contain '.local/bin/idd-critique-telemetry.cmd'
      $render.Lines | Should -Contain '.local/bin/idd-critique-telemetry-report.cmd'
    }
  }

  Context 'an invalid review value' {
    It 'fails the render' {
      $render = Invoke-IgnoreRender -Os 'linux' -CoderabbitJson '{"review": "bogus"}'
      $render.ExitCode | Should -Not -Be 0
      $render.Stderr | Should -Match 'data\.coderabbit\.review'
    }
  }
}
