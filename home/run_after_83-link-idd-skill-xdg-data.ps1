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

# The qualified-root rule of isQualifiedConfigRoot in upstream
# src/scripts/idd-config.mts: on Windows a drive-absolute path or a UNC path;
# elsewhere an absolute path that does not start with //. The value is trimmed
# first, as the installer does. The installer itself refuses Windows, so the
# Windows branch only decides whether this link is made.
$raw = ([string]$env:XDG_DATA_HOME).Trim()
$onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
if ($onWindows) {
  $qualified = ($raw -match '^[A-Za-z]:[\\/]') -or $raw.StartsWith('\\')
} else {
  $qualified = $raw.StartsWith('/') -and -not $raw.StartsWith('//')
}
if (-not $qualified) { exit 0 }

# Normalize with GetFullPath, then drop trailing separators from a non-root
# path only: a drive root such as D:\ keeps its separator, as upstream accepts it.
$xdgDataHome = [System.IO.Path]::GetFullPath($raw)
if ($xdgDataHome -ne [System.IO.Path]::GetPathRoot($xdgDataHome)) {
  $xdgDataHome = $xdgDataHome.TrimEnd('\', '/')
}

# Compare canonical full paths, so a forward-slash or differently cased spelling
# of the same directory counts as the same directory.
$separator = [System.IO.Path]::DirectorySeparatorChar
$canonDefault = [System.IO.Path]::GetFullPath($defaultDataHome).TrimEnd('\', '/')
$canonRendered = [System.IO.Path]::GetFullPath($rendered).TrimEnd('\', '/')
$canonXdg = $xdgDataHome
$ignoreCase = [System.StringComparison]::OrdinalIgnoreCase

if ($canonXdg.Equals($canonDefault, $ignoreCase)) { exit 0 }
# Inside the deployed tree itself: a link there would point back at its own parent.
if ($canonXdg.StartsWith("$canonRendered$separator", $ignoreCase)) { exit 0 }

# A path that reaches the deployed tree through a link on the way down is an
# alias of it, whatever its spelling. Walk from the path up to the root and
# refuse when an existing link on it points at, or inside, the deployed tree.
# A relative link target is taken relative to the link's own directory.
function script:Test-AliasesDeployedTree([string]$path) {
  $p = $path
  while ($p) {
    $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
      $linkDir = Split-Path -Parent $p
      foreach ($linkTarget in @($item.Target)) {
        if (-not $linkTarget) { continue }
        $resolved = if ([System.IO.Path]::IsPathRooted([string]$linkTarget)) {
          [string]$linkTarget
        } else {
          [System.IO.Path]::Combine($linkDir, [string]$linkTarget)
        }
        $full = [System.IO.Path]::GetFullPath($resolved).TrimEnd('\', '/')
        if ($full.Equals($canonRendered, $ignoreCase) -or $full.StartsWith("$canonRendered$separator", $ignoreCase)) {
          return $true
        }
      }
    }
    $parent = Split-Path -Parent $p
    if (-not $parent -or $parent -eq $p) { break }
    $p = $parent
  }
  return $false
}
if (Test-AliasesDeployedTree $xdgDataHome) {
  Write-Warning "idd-skill data: $xdgDataHome reaches the deployed payload through a link; not linking."
  exit 0
}

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
