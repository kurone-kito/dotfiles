#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Verify chezmoi-driven secret deployment status.
.DESCRIPTION
  Reads the manifest rendered by chezmoi at
  ~/.config/chezmoi/secret-deploy-manifest.json (override with -Manifest)
  and prints a colored status table covering all five categories
  (gpg, sshKeys, sshHosts, secretFiles, envFiles).

  Status taxonomy:
    OK      verified present, correct permissions / keyring entry,
            and (when recorded) content matches the last deploy
    DRIFT   present and otherwise valid, but content differs from
            the sha-256 fingerprint recorded at deploy time
    WARN    present but with the wrong mode or related drift
    MISSING expected, not found
    UNKNOWN cannot be verified

  Freshness vs. the secret manager's current contents is intentionally
  NOT checked—use 'chezmoi apply' to refresh.
.PARAMETER Manifest
  Override manifest path (default: ~/.config/chezmoi/secret-deploy-manifest.json).
.PARAMETER Summary
  Emit a one-line status digest (used by the post-apply hook).
.PARAMETER Json
  Emit machine-readable JSON.
.PARAMETER NoColor
  Disable color even when stdout is a TTY.
.NOTES
  Exit codes:
    0  all rows OK
    1  at least one non-OK row (DRIFT, WARN, MISSING, or UNKNOWN)
    2  manifest unreadable or invalid
#>
[CmdletBinding()]
param(
  [string]$Manifest,
  [switch]$Summary,
  [switch]$Json,
  [switch]$NoColor
)

$ErrorActionPreference = 'Stop'

if (-not $Manifest) {
  $Manifest = Join-Path (Join-Path $HOME '.config') (Join-Path 'chezmoi' 'secret-deploy-manifest.json')
}

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------

$useColor = $true
if ($NoColor -or $env:NO_COLOR) {
  $useColor = $false
}
# Disable color when stdout is redirected (e.g., piped or captured).
try {
  if ([Console]::IsOutputRedirected) { $useColor = $false }
} catch { }

$colorMap = @{
  OK      = "`e[32m"
  DRIFT   = "`e[35m"
  WARN    = "`e[33m"
  MISSING = "`e[31m"
  UNKNOWN = "`e[90m"
}
$reset = "`e[0m"
$bold  = "`e[1m"
function Format-Status {
  param([string]$Status)
  if (-not $useColor) { return $Status }
  $c = $colorMap[$Status]
  if (-not $c) { return $Status }
  return "$c$Status$reset"
}

# ---------------------------------------------------------------------------
# Load manifest
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Manifest)) {
  [Console]::Error.WriteLine("secret-status: manifest not found: $Manifest")
  [Console]::Error.WriteLine("  run 'chezmoi apply' to generate it.")
  exit 2
}

try {
  $raw = Get-Content -Raw -LiteralPath $Manifest
  $data = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
  [Console]::Error.WriteLine("secret-status: manifest is not valid JSON: $Manifest")
  exit 2
}

$manifestOs = [string]$data.os
$manager    = [string]$data.manager
$ghqRoot    = [string]$data.ghqRoot

# ---------------------------------------------------------------------------
# Deploy-state loading (for DRIFT detection)
# ---------------------------------------------------------------------------

$statePath = if ($env:SECRET_DEPLOY_STATE) {
  $env:SECRET_DEPLOY_STATE
} else {
  $h = if ($env:HOME) { $env:HOME } else { $HOME }
  Join-Path (Join-Path $h '.config') (Join-Path 'chezmoi' 'secret-deploy-state.json')
}

$stateSha = @{}
if (Test-Path -LiteralPath $statePath) {
  try {
    $sd = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json -ErrorAction Stop
    foreach ($e in @($sd.entries)) {
      if ($e -and $e.path) { $stateSha[[string]$e.path] = [string]$e.sha256 }
    }
  } catch { }
}

function Test-PathDrifted {
  param([string]$Path)
  if ([string]::IsNullOrEmpty($Path)) { return $false }
  if (-not $stateSha.ContainsKey($Path)) { return $false }
  $want = $stateSha[$Path]
  if ([string]::IsNullOrEmpty($want)) { return $false }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  try {
    $got = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
  } catch {
    return $false
  }
  return ($want.ToLowerInvariant() -ne $got)
}

# ---------------------------------------------------------------------------
# Verifier helpers
# ---------------------------------------------------------------------------

function Get-FileOctalMode {
  param([string]$Path)
  if ([string]::IsNullOrEmpty($Path)) { return $null }
  if ($manifestOs -eq 'windows') { return $null }
  try {
    $out = & stat -c '%a' -- $Path 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($out)) {
      $out = & stat -f '%A' -- $Path 2>$null
    }
    if ($LASTEXITCODE -eq 0 -and $out) { return $out.Trim() }
  } catch { }
  return $null
}

function Test-WindowsUserOnlyAcl {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $acl = Get-Acl -LiteralPath $Path
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($ace in $acl.Access) {
      try {
        $sid = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
      } catch { continue }
      $wellKnownAdmins = @('S-1-5-32-544','S-1-5-18') # Administrators, SYSTEM
      if ($sid -ne $me -and $wellKnownAdmins -notcontains $sid) {
        return $false
      }
    }
    return $true
  } catch {
    return $false
  }
}

function Test-FileWithMode {
  param([string]$Path, [string]$WantMode)
  if ([string]::IsNullOrEmpty($Path)) {
    return [pscustomobject]@{ Status = 'UNKNOWN'; Note = 'path not configured' }
  }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Status = 'MISSING'; Note = $Path }
  }
  try {
    $size = (Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Length
  } catch {
    return [pscustomobject]@{ Status = 'MISSING'; Note = $Path }
  }
  if ($size -le 0) {
    return [pscustomobject]@{ Status = 'WARN'; Note = 'file is empty' }
  }
  if ($manifestOs -eq 'windows') {
    if (-not (Test-WindowsUserOnlyAcl -Path $Path)) {
      return [pscustomobject]@{ Status = 'WARN'; Note = 'ACL allows non-owners' }
    }
  } else {
    $mode = Get-FileOctalMode -Path $Path
    if ($mode -and $WantMode -and $mode -ne $WantMode) {
      return [pscustomobject]@{ Status = 'WARN'; Note = "mode $mode, want $WantMode" }
    }
  }
  return [pscustomobject]@{ Status = 'OK'; Note = '' }
}

function Test-Gpg {
  param([string]$Fingerprint)
  if ([string]::IsNullOrEmpty($Fingerprint)) {
    return [pscustomobject]@{ Status = 'UNKNOWN'; Note = 'no expected fingerprint configured' }
  }
  if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Status = 'UNKNOWN'; Note = 'gpg not on PATH' }
  }
  $null = & gpg --list-secret-keys $Fingerprint 2>$null
  if ($LASTEXITCODE -eq 0) {
    return [pscustomobject]@{ Status = 'OK'; Note = 'in keyring' }
  }
  return [pscustomobject]@{ Status = 'MISSING'; Note = 'not in keyring' }
}

function Test-SshKey {
  param([string]$Priv, [string]$Pub)
  $r = Test-FileWithMode -Path $Priv -WantMode '600'
  if ($r.Status -ne 'OK') { return $r }
  $r = Test-FileWithMode -Path $Pub -WantMode '644'
  if ($r.Status -ne 'OK') { return $r }
  if ($manifestOs -ne 'windows') {
    $sshDir = Split-Path -Parent $Priv
    $mode = Get-FileOctalMode -Path $sshDir
    if ($mode -and $mode -ne '700') {
      return [pscustomobject]@{ Status = 'WARN'; Note = ".ssh dir mode $mode, want 700" }
    }
  }
  return [pscustomobject]@{ Status = 'OK'; Note = '' }
}

function Test-SshHost {
  param([string]$Alias, [string]$IdentityPath)
  if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Status = 'UNKNOWN'; Note = 'ssh not on PATH' }
  }
  $eff = & ssh -G $Alias 2>$null
  if (-not $eff -or $LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ Status = 'MISSING'; Note = "alias $Alias not in ssh config" }
  }
  if (-not [string]::IsNullOrEmpty($IdentityPath)) {
    $hasIdentity = $false
    foreach ($line in $eff) {
      $parts = $line -split '\s+', 2
      if ($parts.Length -eq 2 -and $parts[0].ToLowerInvariant() -eq 'identityfile') {
        if ($parts[1].Trim() -eq $IdentityPath) { $hasIdentity = $true; break }
      }
    }
    if (-not $hasIdentity) {
      return [pscustomobject]@{ Status = 'WARN'; Note = "identity $IdentityPath not in effective config" }
    }
    if (-not (Test-Path -LiteralPath $IdentityPath)) {
      return [pscustomobject]@{ Status = 'MISSING'; Note = "identity file $IdentityPath absent" }
    }
  }
  return [pscustomobject]@{ Status = 'OK'; Note = '' }
}

function Test-EnvFile {
  param([string]$AbsPath, [string]$Repo, [string]$Filename)
  if ([string]::IsNullOrEmpty($AbsPath)) {
    return [pscustomobject]@{ Status = 'UNKNOWN'; Note = 'ghq root unresolved' }
  }
  $r = Test-FileWithMode -Path $AbsPath -WantMode '600'
  if ($r.Status -ne 'OK') { return $r }
  # Verify the filename is gitignored.
  $repoRoot = Split-Path -Parent $AbsPath
  $gitMarker = Join-Path $repoRoot '.git'
  if (Test-Path -LiteralPath $gitMarker) {
    $gitignore = Join-Path $repoRoot '.gitignore'
    if (Test-Path -LiteralPath $gitignore) {
      $lines = Get-Content -LiteralPath $gitignore
      $hit = $lines | Where-Object { $_ -eq $Filename -or $_ -eq "/$Filename" }
      if (-not $hit) {
        return [pscustomobject]@{ Status = 'WARN'; Note = "$Filename not in .gitignore" }
      }
    }
  }
  return [pscustomobject]@{ Status = 'OK'; Note = '' }
}

# ---------------------------------------------------------------------------
# Aggregate
# ---------------------------------------------------------------------------

$rows = New-Object System.Collections.Generic.List[object]

function Add-Row {
  param([string]$Status, [string]$Category, [string]$Name, [string]$Target, [string]$Note)
  $rows.Add([pscustomobject]@{
    status   = $Status
    category = $Category
    name     = $Name
    target   = $Target
    note     = $Note
  }) | Out-Null
}

foreach ($e in @($data.categories.gpg)) {
  if (-not $e) { continue }
  $r = Test-Gpg -Fingerprint $e.fingerprint
  $target = if ($e.fingerprint) { $e.fingerprint } else { '?' }
  Add-Row $r.Status 'GPG' $e.label $target $r.Note
}

foreach ($e in @($data.categories.sshKeys)) {
  if (-not $e) { continue }
  $r = Test-SshKey -Priv $e.privatePath -Pub $e.publicPath
  $status = $r.Status; $note = $r.Note
  if ($status -eq 'OK') {
    if (Test-PathDrifted -Path $e.privatePath) {
      $status = 'DRIFT'; $note = 'private key content changed since deploy'
    } elseif (Test-PathDrifted -Path $e.publicPath) {
      $status = 'DRIFT'; $note = 'public key content changed since deploy'
    }
  }
  Add-Row $status 'SSHKEY' $e.label $e.privatePath $note
}

foreach ($e in @($data.categories.sshHosts)) {
  if (-not $e) { continue }
  $r = Test-SshHost -Alias $e.alias -IdentityPath $e.identityPath
  $port = if ($e.port) { $e.port } else { 22 }
  Add-Row $r.Status 'SSHHOST' $e.alias "$($e.hostname):$port" $r.Note
}

foreach ($e in @($data.categories.secretFiles)) {
  if (-not $e) { continue }
  $r = Test-FileWithMode -Path $e.absPath -WantMode '600'
  $status = $r.Status; $note = $r.Note
  if ($status -eq 'OK' -and (Test-PathDrifted -Path $e.absPath)) {
    $status = 'DRIFT'; $note = 'content changed since deploy'
  }
  Add-Row $status 'FILE' $e.label $e.absPath $note
}

foreach ($e in @($data.categories.envFiles)) {
  if (-not $e) { continue }
  $r = Test-EnvFile -AbsPath $e.absPath -Repo $e.repo -Filename $e.filename
  $status = $r.Status; $note = $r.Note
  if ($status -eq 'OK' -and (Test-PathDrifted -Path $e.absPath)) {
    $status = 'DRIFT'; $note = 'content changed since deploy'
  }
  Add-Row $status 'ENV' $e.label $e.absPath $note
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

$okCount      = ($rows | Where-Object status -eq 'OK').Count
$driftCount   = ($rows | Where-Object status -eq 'DRIFT').Count
$warnCount    = ($rows | Where-Object status -eq 'WARN').Count
$missingCount = ($rows | Where-Object status -eq 'MISSING').Count
$unknownCount = ($rows | Where-Object status -eq 'UNKNOWN').Count
$total        = $rows.Count

if ($Json) {
  [pscustomobject]@{ manager = $manager; rows = $rows.ToArray() } |
    ConvertTo-Json -Depth 5
} elseif ($Summary) {
  $line = "secret-status: " +
    "$(Format-Status 'OK') $okCount / " +
    "$(Format-Status 'DRIFT') $driftCount / " +
    "$(Format-Status 'WARN') $warnCount / " +
    "$(Format-Status 'MISSING') $missingCount / " +
    "$(Format-Status 'UNKNOWN') $unknownCount " +
    "(total $total)"
  if ($useColor) { Write-Host "$bold$line$reset" } else { Write-Host $line }
} else {
  $title = "Secret deployment status (manager=$($manager -as [string]), manifest=$Manifest)"
  if ($useColor) { Write-Host "$bold$title$reset" } else { Write-Host $title }
  if ($total -eq 0) {
    Write-Host '  (no deploy targets configured)'
  } else {
    Write-Host ('  {0,-8} {1,-9} {2,-22} {3,-50} {4}' -f 'STATUS','CATEGORY','NAME','TARGET','NOTE')
    foreach ($r in $rows) {
      $line = '  {0,-8} {1,-9} {2,-22} {3,-50} {4}' -f $r.status,$r.category,$r.name,$r.target,$r.note
      if ($useColor) {
        $color = $colorMap[$r.status]
        if ($color) {
          # Replace the leading "  STATUS" prefix with a colored version.
          $statusField = ('{0,-8}' -f $r.status)
          $colored = "  $color$statusField$reset" + $line.Substring(2 + $statusField.Length)
          Write-Host $colored
          continue
        }
      }
      Write-Host $line
    }
  }
  $tally = '  ' +
    "$(Format-Status 'OK') $okCount / " +
    "$(Format-Status 'DRIFT') $driftCount / " +
    "$(Format-Status 'WARN') $warnCount / " +
    "$(Format-Status 'MISSING') $missingCount / " +
    "$(Format-Status 'UNKNOWN') $unknownCount"
  Write-Host $tally
}

if ($driftCount -gt 0 -or $warnCount -gt 0 -or $missingCount -gt 0 -or $unknownCount -gt 0) {
  exit 1
}
exit 0
