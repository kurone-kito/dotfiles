# Default editor for command-line tools (EDITOR and VISUAL).
# Mirrors home/dot_config/shell/conf.d/62-editor.sh, which lists nvim, vim and
# vi. There is deliberately no vim or vi fallback here: Windows has no Vim by
# default, and Microsoft Edit takes its place there.
#
# If nvim resolves as an application command, both variables are set to nvim.
# Otherwise, only on Windows, if edit (Microsoft Edit, `winget install
# Microsoft.Edit`) resolves as an application command, both are set to edit.
# In either case both variables are set even when they were already set. If
# neither command resolves, both variables are left unchanged. edit is
# Windows-only because on other systems that name may be an unrelated command.
#
# Only an Application lookup counts: a function or alias named nvim or edit is
# not something a tool that reads EDITOR can run.
#
# Runs after 30-mise.ps1 so the lookup sees the nvim that mise puts on PATH.
# The whole script runs in a child scope so nothing but the two environment
# variables leaks into the profile. It is PowerShell 5.1 and 7 compatible: no
# ternary, no null-coalescing, no pipeline chain operators, and the OS guard is
# `$IsWindows -ne $false` because $IsWindows is $null on 5.1.

& {
  $editorName = $null
  if (Get-Command nvim -CommandType Application -ErrorAction SilentlyContinue) {
    $editorName = 'nvim'
  } elseif (($IsWindows -ne $false) -and
      (Get-Command edit -CommandType Application -ErrorAction SilentlyContinue)) {
    $editorName = 'edit'
  }

  if ($editorName) {
    $env:EDITOR = $editorName
    $env:VISUAL = $editorName
  }
}
