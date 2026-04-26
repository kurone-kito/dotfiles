# Python venv helper (mise-delegated)
# When mise is active, venv activation is handled automatically.
# This provides a manual fallback for projects not using mise.

function Invoke-VenvActivate {
  if ($env:VIRTUAL_ENV) {
    Write-Warning "Already in venv: $env:VIRTUAL_ENV"
    return
  }
  foreach ($dir in @('.venv', 'venv')) {
    # Windows: Scripts\Activate.ps1, Linux/macOS: bin/Activate.ps1
    foreach ($sub in @('Scripts', 'bin')) {
      $activate = Join-Path (Join-Path $dir $sub) 'Activate.ps1'
      if (Test-Path $activate) {
        & $activate
        return
      }
    }
  }
  Write-Warning 'No .venv or venv directory found'
}

Set-Alias -Name venv-activate -Value Invoke-VenvActivate
