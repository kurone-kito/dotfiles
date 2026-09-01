# Tests for the go-template rendering of
# home/dot_config/ssh/sshd_config.tmpl (see docs/sshd-config-setup.md).
# Renders the real template via `chezmoi execute-template` (mirrors
# winget-user-path-packages-tmpl.Tests.ps1 / 57-setup-mkcert-ca.Tests.ps1)
# so the OS-conditional `Match Group administrators` block gets real
# rendering coverage instead of a hand-copied fixture.
#
# Skipped entirely when chezmoi is not available on PATH (e.g., minimal
# Windows runners).

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoHome = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home' | Resolve-Path
  $script:TemplatePath = Join-Path (Join-Path $script:RepoHome 'dot_config') (Join-Path 'ssh' 'sshd_config.tmpl')

  function Invoke-Render {
    param(
      [string] $Os
    )
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("sshd-config-dest-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    # --override-data-file rather than the inline --override-data string:
    # Windows PowerShell 5.1's native-command argument passing mangles
    # embedded double-quotes in a `{"chezmoi":{"os":"..."}}` style
    # argument (stripping them and producing invalid JSON), unlike
    # PowerShell 7+ -- passing a bare file path instead avoids that
    # native-argv-quoting difference entirely (mirrors
    # 57-setup-mkcert-ca.Tests.ps1's Invoke-Render).
    $overrideDataFile = Join-Path ([IO.Path]::GetTempPath()) ("sshd-config-override-{0}.json" -f [guid]::NewGuid())
    $overrideJson = "{`"chezmoi`":{`"os`":`"$Os`"}}"
    [System.IO.File]::WriteAllText($overrideDataFile, $overrideJson, [System.Text.UTF8Encoding]::new($false))
    try {
      $output = & chezmoi execute-template --file $script:TemplatePath `
        --override-data-file $overrideDataFile `
        --source $script:RepoHome --destination $dest 2>&1
      [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output -join "`n")
      }
    } finally {
      Remove-Item -Path $dest, $overrideDataFile -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe 'sshd_config.tmpl' -Skip:(-not $script:HasChezmoi) {

  Context 'Windows rendering' {
    BeforeAll {
      $script:Render = Invoke-Render -Os 'windows'
      $script:Lines = $script:Render.Output -split "`n"
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'includes a Match Group administrators block' {
      ($script:Lines | Where-Object { $_ -match '^Match Group administrators\s*$' }).Count | Should -Be 1
    }

    It 'the block AuthorizedKeysFile points at the system administrators_authorized_keys file' {
      ($script:Lines | Where-Object {
        $_ -match '^\s*AuthorizedKeysFile\s+__PROGRAMDATA__/ssh/administrators_authorized_keys\s*$'
      }).Count | Should -Be 1
    }

    It 'the Match block is the last section of the rendered file' {
      $trimmed = ($script:Lines | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne '' })
      $trimmed[-2] | Should -Be 'Match Group administrators'
      $trimmed[-1] | Should -Match '^\s*AuthorizedKeysFile\s+__PROGRAMDATA__/ssh/administrators_authorized_keys$'
    }
  }

  Context 'non-Windows rendering' {
    BeforeAll {
      $script:Render = Invoke-Render -Os 'linux'
      $script:Lines = $script:Render.Output -split "`n"
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'produces no Match block' {
      ($script:Lines | Where-Object { $_ -match '^Match\b' }).Count | Should -Be 0
    }
  }
}
