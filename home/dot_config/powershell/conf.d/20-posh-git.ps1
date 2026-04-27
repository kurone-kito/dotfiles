# posh-git (git tab completion for PowerShell)
# https://github.com/dahlbyk/posh-git
# Prompt is handled by Starship; posh-git provides tab completion only.

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
if (-not (Get-Module -ListAvailable posh-git)) { return }

Import-Module posh-git

# Disable posh-git prompt status — Starship handles the prompt.
# This prevents redundant git-status computation on every prompt render.
$GitPromptSettings.EnablePromptStatus = $false
