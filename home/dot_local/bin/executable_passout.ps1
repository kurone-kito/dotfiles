#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Keeps the computer active by simulating user activity.
.DESCRIPTION
    Prevents the PC from entering sleep or screensaver mode by
    simulating periodic user activity.

    On Windows, moves the cursor randomly and sends the BREAK key.
    On macOS, uses caffeinate to block sleep and osascript to
    simulate periodic keystrokes.

    **Caution**: The cursor may move automatically while the program
    runs, so it may interfere with your PC operations.
    To exit, press Ctrl+C.
#>
Set-StrictMode -Version Latest

function Invoke-DotfilesPassoutWindows {
  Add-Type -AssemblyName System.Windows.Forms
  Write-Host 'Keeping PC awake (cursor jiggle)... Press Ctrl+C to stop.'
  while ($true) {
    $pos = [Windows.Forms.Cursor]::Position
    $dx = Get-Random -Minimum -1 -Maximum 2
    $dy = Get-Random -Minimum -1 -Maximum 2
    for ($i = 0; $i -lt 10; $i++) {
      $pos.x += $dx
      $pos.y += $dy
      [Windows.Forms.Cursor]::Position = $pos
      Start-Sleep -Milliseconds 50
    }
    [Windows.Forms.SendKeys]::SendWait('{BREAK}')
    Start-Sleep -Seconds 20
  }
}

function Invoke-DotfilesPassoutMacOS {
  if (-not (Get-Command caffeinate -ErrorAction SilentlyContinue)) {
    Write-Error 'caffeinate not found. Cannot prevent sleep on this Mac.'
    exit 1
  }
  Write-Host 'Keeping Mac awake (caffeinate + keystroke)... Press Ctrl+C to stop.'
  $cafProc = Start-Process caffeinate -ArgumentList '-dimsu' `
    -PassThru -NoNewWindow
  try {
    # Fn key (key code 63) registers as activity without side effects.
    & osascript -e 'tell application "System Events" to key code 63' 2>$null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning (('osascript keystroke failed (exit {0}). ' +
        'Accessibility permission may be missing, or this shell ' +
        'may not have a GUI session. Caffeinate will keep the ' +
        'display awake but keystrokes will not be simulated ' +
        'until the issue is resolved.') -f $LASTEXITCODE)
    }
    while ($true) {
      & osascript -e 'tell application "System Events" to key code 63' 2>$null
      Start-Sleep -Seconds 20
    }
  } finally {
    if ($cafProc -and -not $cafProc.HasExited) {
      Stop-Process -Id $cafProc.Id -ErrorAction SilentlyContinue
    }
  }
}

if ($IsWindows -ne $false) {
  Invoke-DotfilesPassoutWindows
} elseif ($IsMacOS) {
  Invoke-DotfilesPassoutMacOS
} else {
  Write-Warning 'passout.ps1 does not support this platform yet.'
  exit 1
}
