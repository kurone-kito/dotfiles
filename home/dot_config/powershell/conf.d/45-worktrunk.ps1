if (-not (Get-Command git-wt -ErrorAction SilentlyContinue)) { return }

(& git-wt config shell init powershell 2>$null) | Out-String | Invoke-Expression
