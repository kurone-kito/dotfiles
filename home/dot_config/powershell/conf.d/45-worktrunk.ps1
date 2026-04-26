# Prefer git-wt on Windows (avoids Windows Terminal conflict), fall back to wt
$__wtCmd = if (Get-Command git-wt -ErrorAction SilentlyContinue) { 'git-wt' }
           elseif (Get-Command wt -ErrorAction SilentlyContinue) { 'wt' }
           else { $null }
if (-not $__wtCmd) { Remove-Variable __wtCmd -ErrorAction SilentlyContinue; return }

# worktrunk's shell init script ends with a bare "0" that leaks to stdout;
# strip it before evaluating.
$__wtInit = (& $__wtCmd config shell init powershell 2>$null) | Out-String
$__wtInit = $__wtInit -replace '(?m)^0\s*$', ''
if ($__wtInit.Trim()) { Invoke-Expression $__wtInit }
Remove-Variable __wtCmd, __wtInit -ErrorAction SilentlyContinue
