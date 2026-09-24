# Tests for the psmux compatibility wrapper config.
# Exercises: shared tmux sourcing, psmux-specific reload binding, and
# Windows-only deployment through .chezmoiignore.tmpl.

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:PsmuxConfig = Join-Path $repoRoot 'home\dot_psmux.conf'
  $script:TmuxConfig = Join-Path $repoRoot 'home\dot_tmux.conf.tmpl'
  $script:ChezmoiIgnore = Join-Path $repoRoot 'home\.chezmoiignore.tmpl'
  $script:RepoHome = Join-Path $repoRoot 'home'

  function Invoke-TmuxTemplateRender {
    param(
      [string] $Os
    )
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("tmux-conf-dest-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    # --override-data-file rather than the inline --override-data string:
    # Windows PowerShell 5.1's native-command argument passing mangles
    # embedded double-quotes in a `{"chezmoi":{"os":"..."}}` style
    # argument, unlike PowerShell 7+ (mirrors sshd-config-tmpl.Tests.ps1 /
    # 57-setup-mkcert-ca.Tests.ps1's Invoke-Render).
    $overrideDataFile = Join-Path ([IO.Path]::GetTempPath()) ("tmux-conf-override-{0}.json" -f [guid]::NewGuid())
    $overrideJson = "{`"chezmoi`":{`"os`":`"$Os`"}}"
    [System.IO.File]::WriteAllText($overrideDataFile, $overrideJson, [System.Text.UTF8Encoding]::new($false))
    try {
      $output = & chezmoi execute-template --file $script:TmuxConfig `
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

Describe 'psmux config' {

  It 'sources the shared tmux config before enabling psmux-only settings' {
    $lines = Get-Content $script:PsmuxConfig
    $sourceIndex = [Array]::IndexOf($lines, 'source-file ~/.tmux.conf')
    $allowIndex = [Array]::IndexOf($lines, 'set -g allow-predictions on')

    $sourceIndex | Should -BeGreaterOrEqual 0
    $allowIndex | Should -BeGreaterThan $sourceIndex
  }

  It 'never passes the -q flag to psmux source-file, which does not support it' {
    $lines = Get-Content $script:PsmuxConfig

    $lines | Where-Object { $_ -match '^source-file\b' } |
      Should -Not -Match ' -q(\s|$)'
  }

  It 'reloads the psmux wrapper from the shared reload binding' {
    $lines = Get-Content $script:PsmuxConfig

    $lines | Should -Contain 'unbind r'
    $lines | Should -Contain 'bind r source-file ~/.psmux.conf'
  }

  It 'ignores the psmux wrapper on non-Windows platforms' {
    $lines = Get-Content $script:ChezmoiIgnore
    $elseIndex = [Array]::IndexOf($lines, '{{- else }}')
    $endIndex = [Array]::IndexOf($lines, '{{- end }}')
    $nonWindowsLines = $lines[($elseIndex + 1)..($endIndex - 1)]

    $nonWindowsLines | Should -Contain '.psmux.conf'
  }
}

Describe 'dot_tmux.conf.tmpl rendering' -Skip:(-not $script:HasChezmoi) {

  Context 'non-Windows rendering' {
    BeforeAll {
      $script:Render = Invoke-TmuxTemplateRender -Os 'linux'
      $script:Lines = $script:Render.Output -split "`n"
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'still uses source-file -q for the optional shared local tmux config (real tmux supports -q)' {
      $script:Lines | Should -Contain 'source-file -q ~/.tmux.conf.local'
    }
  }

  Context 'Windows rendering' {
    BeforeAll {
      $script:Render = Invoke-TmuxTemplateRender -Os 'windows'
      $script:Lines = $script:Render.Output -split "`n"
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'guards the optional shared local tmux config with a Test-Path if-shell instead of -q' {
      $script:Lines | Should -Contain "if-shell 'Test-Path `$HOME\.tmux.conf.local' 'source-file ~/.tmux.conf.local'"
    }

    It 'never passes the -q flag to psmux source-file, which does not support it' {
      $script:Lines | Where-Object { $_ -match '^source-file\b' } |
        Should -Not -Match ' -q(\s|$)'
    }
  }
}
