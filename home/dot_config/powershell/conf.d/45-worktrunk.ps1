if (-not (Get-Command git-wt -ErrorAction SilentlyContinue)) { return }

# worktrunk's shell init script ends with a bare "0" that leaks to stdout;
# strip it before evaluating.
$__wtInit = (& git-wt config shell init powershell 2>$null) | Out-String
$__wtInit = $__wtInit -replace '(?m)^0\s*$', ''
if ($__wtInit.Trim()) { Invoke-Expression $__wtInit }
Remove-Variable __wtInit -ErrorAction SilentlyContinue
