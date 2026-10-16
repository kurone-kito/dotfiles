# chezmoi run_after script: bridge the vendored IDD payload data root to a
# customized XDG_DATA_HOME.
#
# idd-skill resolves its installed payload at $XDG_DATA_HOME/idd-skill, falling
# back to $HOME/.local/share/idd-skill only when XDG_DATA_HOME is unset or is not
# a qualified root. chezmoi's own dot_local/share source-path convention always
# deploys home/dot_local/share/idd-skill to the fixed $HOME/.local/share location,
# so a custom XDG_DATA_HOME would otherwise never see the vendored payload. This
# script links $XDG_DATA_HOME/idd-skill to that deployed tree when the root
# differs from ~/.local/share. Runs every apply (not run_once/run_onchange) since
# it only depends on the current process environment, not chezmoi source content.
#
# The link sits at the installer's own data-root path. The installer refuses to
# write through a symlinked data root, so a later installer run under this custom
# root is refused. That run is out of scope here (see #648 and #649).
$ErrorActionPreference = 'Stop'

$defaultDataHome = Join-Path (Join-Path $HOME '.local') 'share'
$rendered = Join-Path $defaultDataHome 'idd-skill'

# Trim surrounding whitespace and trailing separators before the qualified-root
# test. The trailing-separator strip mirrors the installer's path normalization.
$xdgDataHome = ([string]$env:XDG_DATA_HOME).Trim().TrimEnd('\', '/')

# The qualified-root rule of isQualifiedConfigRoot in upstream
# src/scripts/idd-config.mts: on Windows a drive-absolute path or a UNC path;
# elsewhere an absolute path that does not start with //. The installer itself
# refuses Windows, so the Windows branch only decides whether this link is made.
$onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
if ($onWindows) {
  $qualified = ($xdgDataHome -match '^[A-Za-z]:[\\/]') -or $xdgDataHome.StartsWith('\\')
} else {
  $qualified = $xdgDataHome.StartsWith('/') -and -not $xdgDataHome.StartsWith('//')
}
if (-not $qualified) { exit 0 }

# Compare canonical full paths, so a forward-slash or differently cased spelling
# of the same directory counts as the same directory.
$separator = [System.IO.Path]::DirectorySeparatorChar
$canonDefault = [System.IO.Path]::GetFullPath($defaultDataHome).TrimEnd('\', '/')
$canonRendered = [System.IO.Path]::GetFullPath($rendered).TrimEnd('\', '/')
$canonXdg = [System.IO.Path]::GetFullPath($xdgDataHome).TrimEnd('\', '/')
$ignoreCase = [System.StringComparison]::OrdinalIgnoreCase

if ($canonXdg.Equals($canonDefault, $ignoreCase)) { exit 0 }
# Inside the deployed tree itself: a link there would point back at its own parent.
if ($canonXdg.StartsWith("$canonRendered$separator", $ignoreCase)) { exit 0 }

if (-not (Test-Path -LiteralPath $rendered -PathType Container)) { exit 0 }

$target = Join-Path $xdgDataHome 'idd-skill'

$existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
if ($existing) {
  $isLink = $existing.LinkType -in @('SymbolicLink', 'Junction')
  if ($isLink) {
    foreach ($linkTarget in @($existing.Target)) {
      if ($linkTarget -and [System.IO.Path]::GetFullPath([string]$linkTarget).TrimEnd('\', '/').Equals($canonRendered, $ignoreCase)) {
        exit 0
      }
    }
    Write-Warning "idd-skill data: $target is a link to a different target; not overwriting."
    exit 0
  }
  Write-Warning "idd-skill data: $target already exists and is not a link; not overwriting."
  exit 0
}

if (-not (Test-Path -LiteralPath $xdgDataHome -PathType Container)) {
  $null = New-Item -ItemType Directory -Path $xdgDataHome -Force
}

try {
  $null = New-Item -ItemType SymbolicLink -Path $target -Target $rendered
  Write-Host "idd-skill data: linked $target -> $rendered"
} catch {
  # A symbolic link needs elevation or Developer Mode on Windows; a directory
  # junction does not. Copying the tree is not an option: it would not follow
  # later applies.
  try {
    $null = New-Item -ItemType Junction -Path $target -Target $rendered
    Write-Host "idd-skill data: created a directory junction $target -> ${rendered} (symlink unavailable: $($_.Exception.Message))"
  } catch {
    Write-Warning "idd-skill data: could not link $target -> ${rendered}: $($_.Exception.Message)"
  }
}
