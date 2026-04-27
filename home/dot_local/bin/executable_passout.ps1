#!/usr/bin/env pwsh

<#
.SYNOPSIS
    A script that moves the cursor randomly to keep the PC active.
.DESCRIPTION
    This script moves the cursor randomly and sends the BREAK key
    periodically to prevent the PC from going into sleep or screensaver mode.

    **Caution**: The cursor will move automatically while the program runs,
    so that it may interfere with your PC operations. To exit, press Ctrl+C.
+#>
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms
while ($true) {
  $POSITION = [Windows.Forms.Cursor]::Position
  $DX = (Get-Random -Minimum -1 -Maximum 2)
  $DY = (Get-Random -Minimum -1 -Maximum 2)
  for ($I=0; $I -lt 10; $I+=1) {
    $POSITION.x += $DX
    $POSITION.y += $DY
    [Windows.Forms.Cursor]::Position = $POSITION
    Start-Sleep -Milliseconds 50
  }
  [Windows.Forms.SendKeys]::SendWait("{BREAK}")

  Start-Sleep -Seconds 20
}
