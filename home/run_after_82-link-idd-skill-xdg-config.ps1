# chezmoi run_after script: bridge the rendered IDD critique-delegate
# config to a customized XDG_CONFIG_HOME.
#
# idd-skill resolves this file at $XDG_CONFIG_HOME/idd-skill/config.json,
# falling back to $HOME/.config/idd-skill/config.json only when
# XDG_CONFIG_HOME is unset. chezmoi's own dot_config source-path
# convention always deploys home/dot_config/idd-skill/config.json.tmpl to
# the fixed $HOME/.config location regardless of a customized
# XDG_CONFIG_HOME, so a custom XDG_CONFIG_HOME would otherwise never see
# the delegate config at all. Runs every apply (not run_once/run_onchange)
# since it only depends on the current process environment, not chezmoi
# source content.
$ErrorActionPreference = 'Stop'

$xdgConfigHome = $env:XDG_CONFIG_HOME
$defaultConfigHome = Join-Path $HOME '.config'
if (-not $xdgConfigHome) { $xdgConfigHome = $defaultConfigHome }

if ($xdgConfigHome -eq $defaultConfigHome) {
  exit 0
}

$rendered = Join-Path $defaultConfigHome (Join-Path 'idd-skill' 'config.json')
if (-not (Test-Path -LiteralPath $rendered -PathType Leaf)) {
  exit 0
}

$targetDir = Join-Path $xdgConfigHome 'idd-skill'
$target = Join-Path $targetDir 'config.json'

$existing = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
if ($existing) {
  $isSymlink = $existing.LinkType -eq 'SymbolicLink'
  if ($isSymlink -and $existing.Target -contains $rendered) {
    exit 0
  }
  if ($isSymlink) {
    Write-Warning "idd-skill config: $target is a symlink to a different target; not overwriting."
    exit 0
  }
  Write-Warning "idd-skill config: $target already exists and is not a symlink; not overwriting."
  exit 0
}

if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
  $null = New-Item -ItemType Directory -Path $targetDir -Force
}

try {
  $null = New-Item -ItemType SymbolicLink -Path $target -Target $rendered -Force
  Write-Host "idd-skill config: linked $target -> $rendered"
} catch [System.Exception] {
  # Symlink creation needs elevation or Developer Mode on Windows -- fall
  # back to a plain copy so the config is still discoverable, even though
  # it will not automatically stay in sync with future chezmoi applies.
  Copy-Item -LiteralPath $rendered -Destination $target -Force
  Write-Host "idd-skill config: copied $rendered -> $target (symlink unavailable: $($_.Exception.Message))"
}
