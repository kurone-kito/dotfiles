#!/usr/bin/env pwsh
# Review one issue draft with the CodeRabbit CLI, as the IDD issue-authoring
# delegate (issueAuthoring.adversarialReview.delegate). PowerShell twin of the
# POSIX executable_coderabbit-authoring-review, for Windows PowerShell 5.1 and
# PowerShell 7. Reads one JSON object {title, body, packet} on stdin, commits it
# as draft.md in a temporary git repository outside the caller's checkout,
# runs `coderabbit review` there, and prints the review text on stdout.
#
# Fails (non-zero exit, empty stdout) when the review cannot run or does not
# exit 0. The caller's checkout is never touched. The temporary repository is
# removed afterwards only when it still matches what this script created;
# otherwise it is kept and its path is printed on stderr.
#
# CODERABBIT_CRITIQUE_TIMEOUT (default 300 seconds) bounds the auth probe and
# the review. CODERABBIT_CRITIQUE_DEEP set to 1, true or yes (case-insensitive)
# adds --deep, as the critique launcher does.

$ErrorActionPreference = 'Stop'

function Write-Usage {
  [Console]::Out.WriteLine('Usage: coderabbit-authoring-review')
}

function Stop-WithError([string]$message) {
  [Console]::Error.WriteLine("coderabbit-authoring-review: $message")
  exit 1
}

if ($args.Count -gt 0) {
  if ($args.Count -eq 1 -and ($args[0] -eq '--help' -or $args[0] -eq '-h')) {
    Write-Usage
    exit 0
  }
  [Console]::Error.WriteLine('Usage: coderabbit-authoring-review')
  exit 2
}

# Git variables that would point git calls at the caller's repository.
foreach ($name in 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_NAMESPACE') {
  Remove-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue
}

$timeoutSeconds = 300
$rawTimeout = $env:CODERABBIT_CRITIQUE_TIMEOUT
if ($rawTimeout -match '^[0-9]+$' -and [int]$rawTimeout -gt 0) {
  $timeoutSeconds = [int]$rawTimeout
}

$coderabbit = Get-Command coderabbit -ErrorAction SilentlyContinue
if ($null -eq $coderabbit) {
  Stop-WithError 'coderabbit is not on PATH'
}
$coderabbitPath = $coderabbit.Source

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $git) {
  Stop-WithError 'git is required to commit the draft; failing closed'
}
$gitPath = $git.Source

# Read the draft and check its exact shape before anything is created.
$raw = [Console]::In.ReadToEnd()
$draft = $null
try {
  $draft = $raw | ConvertFrom-Json
} catch {
  $draft = $null
}

function Test-NonEmptyString($value) {
  return ($value -is [string]) -and ($value.Length -gt 0)
}

function Test-StringArray($value) {
  if ($value -isnot [System.Array]) {
    return $false
  }
  foreach ($item in $value) {
    if (-not (Test-NonEmptyString $item)) {
      return $false
    }
  }
  return $true
}

$shapeOk = $false
if ($null -ne $draft -and $draft -is [pscustomobject]) {
  $topKeys = @($draft.PSObject.Properties.Name | Sort-Object) -join ','
  $packet = $draft.packet
  if ($topKeys -ceq 'body,packet,title' -and $packet -is [pscustomobject]) {
    $packetKeys = @($packet.PSObject.Properties.Name | Sort-Object) -join ','
    $shapeOk = ($packetKeys -ceq 'checklist,constraints,evidence,goal,relationships') `
      -and (Test-NonEmptyString $draft.title) `
      -and (Test-NonEmptyString $draft.body) `
      -and (Test-NonEmptyString $packet.goal) `
      -and (Test-StringArray $packet.constraints) `
      -and (Test-StringArray $packet.evidence) `
      -and (Test-StringArray $packet.relationships) `
      -and (Test-StringArray $packet.checklist)
  }
}
if (-not $shapeOk) {
  Stop-WithError 'stdin is not one draft object with title, body and packet of the expected shape'
}

# Refuse a temporary directory inside the caller's checkout.
$tempBase = [IO.Path]::GetTempPath().TrimEnd([IO.Path]::DirectorySeparatorChar)
$callerTop = & $gitPath rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($callerTop)) {
  $prefix = $callerTop.TrimEnd('/', '\') + [IO.Path]::DirectorySeparatorChar
  if ($tempBase.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-WithError 'the temporary directory is inside the current checkout; point TEMP or TMPDIR outside it'
  }
}

$root = Join-Path $tempBase ('coderabbit-authoring-review.' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$workDir = Join-Path $tempBase ('coderabbit-authoring-review-work.' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir | Out-Null

$script:RootReady = $true

function Invoke-GitInRoot {
  param([string[]]$Arguments)
  $gitArguments = @('-C', $root,
    '-c', 'user.name=coderabbit-authoring-review',
    '-c', 'user.email=coderabbit-authoring-review@invalid',
    '-c', 'commit.gpgsign=false',
    '-c', 'core.hooksPath=NUL') + $Arguments
  & $gitPath @gitArguments > $null 2>&1
  return $LASTEXITCODE
}

function Quote-Argument([string]$value) {
  if ($value -match '[\s"]' -or $value.Length -eq 0) {
    return '"' + ($value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
  }
  return $value
}

# Run a program bounded by the timeout, with GIT_OPTIONAL_LOCKS=0 in its
# environment and the given working directory. Only this process handle is
# ever killed.
function Invoke-Bounded {
  param([string]$FileName, [string[]]$Arguments, [string]$WorkingDirectory, [int]$Seconds)
  $startInfo = New-Object Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FileName
  $startInfo.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
  $startInfo.WorkingDirectory = $WorkingDirectory
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.EnvironmentVariables['GIT_OPTIONAL_LOCKS'] = '0'
  $process = [Diagnostics.Process]::Start($startInfo)
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit($Seconds * 1000)) {
    $process.Kill()
    $process.WaitForExit()
    return @{ Code = -1; Out = ''; Err = '' }
  }
  $process.WaitForExit()
  return @{ Code = $process.ExitCode; Out = $stdoutTask.Result; Err = $stderrTask.Result }
}

# One line per path under the root: type, SHA-256 for files, and the path.
# Reparse points are recorded as links and never descended into.
function Get-RootSnapshot {
  $records = New-Object 'System.Collections.Generic.List[string]'
  $stack = New-Object 'System.Collections.Generic.Stack[string]'
  $stack.Push($root)
  while ($stack.Count -gt 0) {
    $directory = $stack.Pop()
    foreach ($child in Get-ChildItem -LiteralPath $directory -Force) {
      $isLink = ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
      if ($isLink) {
        $records.Add("l`t-`t" + $child.FullName)
      } elseif ($child.PSIsContainer) {
        $records.Add("d`t-`t" + $child.FullName)
        $stack.Push($child.FullName)
      } else {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $child.FullName).Hash
        $records.Add("f`t" + $hash + "`t" + $child.FullName)
      }
    }
  }
  $sorted = New-Object 'System.Collections.Generic.List[string]'
  $sorted.AddRange($records)
  $sorted.Sort([StringComparer]::Ordinal)
  return ,$sorted
}

function Remove-RootIfUnchanged([System.Collections.Generic.List[string]]$expected) {
  $current = Get-RootSnapshot
  $same = ($current.Count -eq $expected.Count)
  if ($same) {
    for ($i = 0; $i -lt $current.Count; $i++) {
      if ($current[$i] -cne $expected[$i]) {
        $same = $false
        break
      }
    }
  }
  if (-not $same) {
    [Console]::Error.WriteLine("coderabbit-authoring-review: kept temporary repository at $root (its contents differ from what this run created)")
    return
  }
  $records = @($expected | Sort-Object { $_.Length } -Descending)
  foreach ($record in $records) {
    $parts = $record -split "`t", 3
    $type = $parts[0]
    $path = $parts[2]
    if ($type -eq 'd') {
      [IO.Directory]::Delete($path, $false)
    } elseif ($type -eq 'l') {
      if (Test-Path -LiteralPath $path -PathType Container) {
        [IO.Directory]::Delete($path, $false)
      } else {
        [IO.File]::Delete($path)
      }
    } else {
      [IO.File]::Delete($path)
    }
  }
  [IO.Directory]::Delete($root, $false)
}

$exitCode = 1
$reviewText = ''
try {
  Invoke-GitInRoot @('init', '-q') | Out-Null
  if ((Invoke-GitInRoot @('commit', '-q', '--allow-empty', '-m', 'empty base')) -ne 0) {
    Stop-WithError 'cannot commit the empty base'
  }
  $base = (& $gitPath -C $root rev-parse HEAD 2>$null).Trim()

  $lines = New-Object 'System.Collections.Generic.List[string]'
  $lines.Add('# ' + $draft.title)
  $lines.Add('')
  $lines.Add($draft.body)
  $lines.Add('')
  $lines.Add('## Goal')
  $lines.Add('')
  $lines.Add($draft.packet.goal)
  $lines.Add('')
  $lines.Add('## Constraints')
  $lines.Add('')
  foreach ($item in $draft.packet.constraints) { $lines.Add('- ' + $item) }
  $lines.Add('')
  $lines.Add('## Evidence')
  $lines.Add('')
  foreach ($item in $draft.packet.evidence) { $lines.Add('- ' + $item) }
  $lines.Add('')
  $lines.Add('## Relationships')
  $lines.Add('')
  foreach ($item in $draft.packet.relationships) { $lines.Add('- ' + $item) }
  $lines.Add('')
  $lines.Add('## Checklist')
  $lines.Add('')
  foreach ($item in $draft.packet.checklist) { $lines.Add('- [ ] ' + $item) }
  $text = ($lines -join "`n") + "`n"
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText((Join-Path $root 'draft.md'), $text, $utf8)

  if ((Invoke-GitInRoot @('add', 'draft.md')) -ne 0) { Stop-WithError 'cannot stage draft.md' }
  if ((Invoke-GitInRoot @('commit', '-q', '-m', 'issue draft')) -ne 0) { Stop-WithError 'cannot commit draft.md' }

  # Freeze what this run created. Anything that appears under the root later
  # is not ours and keeps the directory in place.
  $expected = Get-RootSnapshot

  [Console]::Error.WriteLine('coderabbit-authoring-review: reviewing the draft in a temporary repository')

  $probe = Invoke-Bounded -FileName $coderabbitPath -Arguments @('auth', 'status', '--agent') -WorkingDirectory $root -Seconds $timeoutSeconds
  $authenticated = $false
  if ($probe.Code -eq 0) {
    try {
      $authenticated = (($probe.Out | ConvertFrom-Json).authenticated -eq $true)
    } catch {
      $authenticated = $false
    }
  }
  if (-not $authenticated) {
    Stop-WithError 'the auth probe failed, timed out, or reports not authenticated'
  }

  $reviewArguments = @('review', '--agent', '--base', $base)
  $deepValue = [string]$env:CODERABBIT_CRITIQUE_DEEP
  if ($deepValue -match '^(1|true|yes)$') {
    $reviewArguments += '--deep'
  }
  $review = Invoke-Bounded -FileName $coderabbitPath -Arguments $reviewArguments -WorkingDirectory $root -Seconds $timeoutSeconds
  if ($review.Code -eq 0) {
    $reviewText = $review.Out
    $exitCode = 0
  } else {
    $exitCode = $review.Code
    if ($exitCode -lt 0) { $exitCode = 1 }
  }

  if ($exitCode -eq 0) {
    [Console]::Out.Write($reviewText)
  }
} finally {
  if (Test-Path -LiteralPath $root -PathType Container) {
    try {
      if ($null -ne $expected) {
        Remove-RootIfUnchanged $expected
      } else {
        [Console]::Error.WriteLine("coderabbit-authoring-review: kept temporary repository at $root")
      }
    } catch {
      [Console]::Error.WriteLine("coderabbit-authoring-review: kept temporary repository at $root (removal stopped)")
    }
  }
  if (Test-Path -LiteralPath $workDir -PathType Container) {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

exit $exitCode
