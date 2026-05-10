# Tests for the psmux compatibility wrapper config.
# Exercises: shared tmux sourcing, psmux-specific reload binding, and
# Windows-only deployment through .chezmoiignore.tmpl.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:PsmuxConfig = Join-Path $repoRoot 'home\dot_psmux.conf'
  $script:TmuxConfig = Join-Path $repoRoot 'home\dot_tmux.conf'
  $script:ChezmoiIgnore = Join-Path $repoRoot 'home\.chezmoiignore.tmpl'
}

Describe 'psmux config' {

  It 'sources the shared tmux config before enabling psmux-only settings' {
    $lines = Get-Content $script:PsmuxConfig
    $sourceIndex = [Array]::IndexOf($lines, 'source-file -q ~/.tmux.conf')
    $allowIndex = [Array]::IndexOf($lines, 'set -g allow-predictions on')

    $sourceIndex | Should -BeGreaterOrEqual 0
    $allowIndex | Should -BeGreaterThan $sourceIndex
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

  It 'uses source-file -q for the optional shared local tmux config' {
    $lines = Get-Content $script:TmuxConfig

    $lines | Should -Contain 'source-file -q ~/.tmux.conf.local'
  }
}
