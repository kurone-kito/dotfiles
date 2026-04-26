# thefuck (command correction) initialization
# https://github.com/nvbn/thefuck

if (-not (Get-Command thefuck -ErrorAction SilentlyContinue)) { return }

# thefuck may fail on Python 3.12+ (removed imp module); suppress errors
$_tfAlias = try { thefuck --alias 2>$null | Out-String } catch { '' }
if ($_tfAlias) { Invoke-Expression $_tfAlias }
Remove-Variable _tfAlias -ErrorAction SilentlyContinue
