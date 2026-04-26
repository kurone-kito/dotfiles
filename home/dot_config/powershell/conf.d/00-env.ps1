# PowerShell environment configuration

# Encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# PSReadLine configuration
# Guard: skip when PSReadLine is not loaded (e.g., non-interactive hosts, psmux)
if ((Get-Module PSReadLine) -and [Console]::IsInputRedirected -eq $false) {
  try {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -HistoryNoDuplicates:$true
    # PredictionSource requires PSReadLine 2.2+ (PowerShell 7.2+)
    if ((Get-Module PSReadLine).Version -ge [version]'2.2.0') {
      Set-PSReadLineOption -PredictionSource History
    }
  } catch {
    # PSReadLine may not be fully initialized in some hosts
  }
}
