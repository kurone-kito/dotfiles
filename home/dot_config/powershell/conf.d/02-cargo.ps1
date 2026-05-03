# Prepend Cargo's bin directory to PATH on Unix pwsh.
#
# On Windows, 01-path.ps1 already manages this via Get-StaticManagedPaths
# (which is also the source of truth for the User PATH registry writer in
# run_onchange_after_35-register-path.ps1.tmpl), so this script returns
# early to avoid double-prepending.
#
# This conf.d entry exists so users can install Rust via
# "rustup-init --no-modify-path" without losing PATH integration and
# without rustup mutating chezmoi-managed shell rc files.

if ($IsWindows) { return }

& {
  $cargoHome = if ([string]::IsNullOrEmpty($env:CARGO_HOME)) {
    Join-Path $HOME '.cargo'
  } else {
    $env:CARGO_HOME
  }
  $cargoBin = Join-Path $cargoHome 'bin'

  if (-not (Test-Path -LiteralPath $cargoBin -PathType Container)) {
    return
  }

  $sep = [IO.Path]::PathSeparator
  $entries = if ([string]::IsNullOrEmpty($env:PATH)) {
    @()
  } else {
    $env:PATH.Split($sep)
  }

  foreach ($entry in $entries) {
    if ($entry -ceq $cargoBin) { return }
  }

  $env:PATH = if ($entries.Count -eq 0) {
    $cargoBin
  } else {
    $cargoBin + $sep + ($entries -join $sep)
  }
}
