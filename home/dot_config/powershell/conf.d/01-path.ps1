# Prepend known tool directories to PATH when they exist on disk.
# Session-level fallback — the primary mechanism is the chezmoi
# run_onchange script (35-register-path) which persists these in
# the Windows User PATH registry.  This covers tools installed
# between chezmoi runs and SSH sessions where registry PATH may
# not be fully propagated.

# Windows-only: manage user-scoped tool directories here.
if ($IsWindows -eq $false) { return }

$sep = [IO.Path]::PathSeparator
$extraPaths = @(
  (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
  (Join-Path $env:LOCALAPPDATA 'Zellij')
  (Join-Path ${env:ProgramFiles(x86)} 'GnuWin32\bin')
  (Join-Path $HOME '.local\bin')
)

foreach ($dir in $extraPaths) {
  if ((Test-Path $dir) -and ($env:PATH -split [regex]::Escape($sep) -notcontains $dir)) {
    $env:PATH = "$dir$sep$env:PATH"
  }
}
