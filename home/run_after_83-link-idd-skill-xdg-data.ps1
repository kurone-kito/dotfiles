# chezmoi run_after script: bridge the vendored IDD payload data root to a
# customized XDG_DATA_HOME, and create the Windows `current` pointer.
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
#
# On Windows the template ignores the `current` symlink, because creating a
# symbolic link needs privilege. This script creates `current` as a directory
# junction instead, which needs none, so the entry path resolves there too. It
# never replaces an existing `current`: a real directory is left alone, and a
# link to another version is reported.
$ErrorActionPreference = 'Stop'

$onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$defaultDataHome = Join-Path (Join-Path $HOME '.local') 'share'
$rendered = Join-Path $defaultDataHome 'idd-skill'
$separator = [System.IO.Path]::DirectorySeparatorChar
# Windows paths are compared without case; other platforms compare exactly.
$ignoreCase = if ($onWindows) {
  [System.StringComparison]::OrdinalIgnoreCase
} else {
  [System.StringComparison]::Ordinal
}
# The payload version the `current` pointer names. It must match the content of
# home/dot_local/share/idd-skill/symlink_current; a Pester case checks that.
$version = '0.16.0'

# The physical form of a path, as the OS resolves it: each symbolic link or
# junction on the way is followed, and the rest of the path is appended to its
# target. A relative target is taken from the link's own directory; a rooted
# target without a drive, such as \Users\x, is on the drive of the link. On
# POSIX a ".." after a link goes to the parent of the link's target; on Windows
# ".." is collapsed lexically before the walk, as the Win32 path APIs do.
# PowerShell 5.1 reports a share target as UNC\server\share, which is read back
# as \\server\share. A volume mount point (a Volume{GUID} target) is not
# followed. Returns $null past 16 links. Other aliases, such as subst drives and
# UNC administrative shares, are not resolved.
function script:Get-PhysicalPath([string]$path, [int]$depth = 0) {
  if ($depth -gt 16) { return $null }
  # On Windows, GetFullPath expands an 8.3 short name to its long form (for a
  # path that exists), so a short-form path compares equal to its long form. It
  # also collapses ".." lexically, as the Win32 path APIs do. On POSIX the walk
  # keeps ".." physical.
  if ($onWindows) {
    try { $path = [System.IO.Path]::GetFullPath($path) } catch { }
  }
  $root = [System.IO.Path]::GetPathRoot($path)
  $parts = @($path.Substring($root.Length).Split(
      [char[]]@('\', '/'), [System.StringSplitOptions]::RemoveEmptyEntries))
  $current = $root
  for ($i = 0; $i -lt $parts.Count; $i++) {
    $part = $parts[$i]
    if ($part -eq '.') { continue }
    if ($part -eq '..') {
      $parent = [System.IO.Path]::GetDirectoryName($current)
      if ($parent) { $current = $parent }
      continue
    }
    $candidate = [System.IO.Path]::Combine($current, $part)
    $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
    $linkTarget = ''
    if ($item -and $item.LinkType -and $item.Target) {
      $linkTarget = [string]@($item.Target)[0]
    }
    if ($linkTarget -like 'UNC\*') { $linkTarget = '\\' + $linkTarget.Substring(4) }
    if ($linkTarget -and $linkTarget -notmatch 'Volume\{') {
      if (-not [System.IO.Path]::IsPathRooted($linkTarget)) {
        $next = [System.IO.Path]::Combine($current, $linkTarget)
      } elseif ([System.IO.Path]::GetPathRoot($linkTarget) -match '^[\\/]$') {
        $next = [System.IO.Path]::Combine(
          [System.IO.Path]::GetPathRoot($current), $linkTarget.TrimStart('\', '/'))
      } else {
        $next = $linkTarget
      }
      for ($j = $i + 1; $j -lt $parts.Count; $j++) {
        $next = [System.IO.Path]::Combine($next, $parts[$j])
      }
      return (Get-PhysicalPath $next ($depth + 1))
    }
    $current = $candidate
  }
  return $current
}

if ($onWindows) {
  $currentPointer = Join-Path $rendered 'current'
  $versionDir = Join-Path $rendered $version
  if (Test-Path -LiteralPath $versionDir -PathType Container) {
    $currentItem = Get-Item -LiteralPath $currentPointer -Force -ErrorAction SilentlyContinue
    if (-not $currentItem) {
      try {
        $null = New-Item -ItemType Junction -Path $currentPointer -Target $versionDir
        Write-Host "idd-skill data: created a directory junction $currentPointer -> $versionDir"
      } catch {
        Write-Warning "idd-skill data: could not create ${currentPointer}: $($_.Exception.Message)"
      }
    } elseif ($currentItem.LinkType -in @('SymbolicLink', 'Junction')) {
      $physCurrent = Get-PhysicalPath $currentPointer
      $physVersion = Get-PhysicalPath $versionDir
      if (-not ($physCurrent -and $physVersion -and $physCurrent.Equals($physVersion, $ignoreCase))) {
        $currentTarget = [string]@($currentItem.Target)[0]
        Write-Warning "idd-skill data: $currentPointer points at $currentTarget, not $version; not overwriting."
      }
    } else {
      Write-Warning "idd-skill data: $currentPointer is not a link; not overwriting."
    }
  }
}

# The qualified-root rule of isQualifiedConfigRoot in upstream
# src/scripts/idd-config.mts: on Windows a drive-absolute path or a UNC path;
# elsewhere an absolute path that does not start with //. The value is trimmed
# first, as the installer does.
$raw = ([string]$env:XDG_DATA_HOME).Trim()
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

# Compare physical paths, so a link on the way, a different spelling, letter
# case or 8.3 short name of the same directory counts as the same directory. A
# root that resolves to the deployed tree, or to anything inside it, is refused:
# a link there would point back into its own payload.
$physRendered = Get-PhysicalPath $rendered
$physDefault = Get-PhysicalPath $defaultDataHome
$physXdg = Get-PhysicalPath $xdgDataHome
if (-not $physRendered -or -not $physDefault -or -not $physXdg) {
  Write-Warning 'idd-skill data: the links on the way to the data root or the payload nest too deeply; not linking.'
  exit 0
}
if ($physXdg.Equals($physDefault, $ignoreCase)) { exit 0 }
if ($physXdg.Equals($physRendered, $ignoreCase) -or $physXdg.StartsWith("$physRendered$separator", $ignoreCase)) {
  Write-Warning "idd-skill data: $xdgDataHome resolves to the deployed payload or into it; not linking."
  exit 0
}

if (-not (Test-Path -LiteralPath $rendered -PathType Container)) { exit 0 }

$target = Join-Path $xdgDataHome 'idd-skill'

$existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
if ($existing) {
  if ($existing.LinkType -in @('SymbolicLink', 'Junction')) {
    $physLink = Get-PhysicalPath $target
    if ($physLink -and $physLink.Equals($physRendered, $ignoreCase)) { exit 0 }
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
