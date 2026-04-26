# PowerShell profile (all platforms)
# Sources conf.d drop-in scripts, then initializes the prompt.
# Uses nested Join-Path for PowerShell 5 compatibility.

$confDir = Join-Path (Join-Path (Join-Path $HOME '.config') 'powershell') 'conf.d'
if (Test-Path $confDir) {
  Get-ChildItem (Join-Path $confDir '*.ps1') |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }
}

# Prompt
if (Get-Command starship -ErrorAction SilentlyContinue) {
  function Invoke-Starship-TransientFunction {
    &starship module character
  }
  Invoke-Expression (&starship init powershell)
  Enable-TransientPrompt
}
