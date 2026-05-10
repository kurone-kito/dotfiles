# PowerShell environment configuration

# Encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# PSReadLine requires an interactive console.
function global:Test-DotfilesPSReadLineInteractive {
  return (
    [Environment]::UserInteractive -and
    [Console]::IsInputRedirected -eq $false -and
    [Console]::IsOutputRedirected -eq $false
  )
}

function global:Get-DotfilesPSReadLineModule {
  return Get-Module -Name PSReadLine
}

function global:Test-DotfilesPSReadLineDeferredHost {
  return (
    (-not [string]::IsNullOrEmpty($env:TMUX)) -or
    (-not [string]::IsNullOrEmpty($env:TMUX_PANE)) -or
    (-not [string]::IsNullOrEmpty($env:PSMUX))
  )
}

function global:Test-DotfilesPSReadLineReady {
  if (-not (Test-DotfilesPSReadLineInteractive)) {
    return $false
  }

  if (-not (Get-DotfilesPSReadLineModule)) {
    return $false
  }

  try {
    [void][Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems()
    return $true
  } catch [System.Exception] {
    return $false
  }
}

function global:Test-DotfilesVSCodeTerminal {
  return $env:TERM_PROGRAM -eq 'vscode'
}

function global:Get-DotfilesPSReadLineSettings {
  param(
    [AllowNull()]
    [object] $Module = (Get-DotfilesPSReadLineModule)
  )

  $editMode = 'Emacs'

  $settings = [ordered]@{
    EditMode = $editMode
    HistoryNoDuplicates = $true
    PredictionSource = $null
  }

  # PredictionSource requires PSReadLine 2.2+ (PowerShell 7.2+).
  if ($null -ne $Module -and $Module.Version -ge [version]'2.2.0') {
    $settings.PredictionSource = 'History'
  }

  return [pscustomobject]$settings
}

function global:Set-DotfilesPSReadLineSettings {
  param(
    [Parameter(Mandatory)]
    [pscustomobject] $Settings
  )

  try {
    Set-PSReadLineOption -EditMode $Settings.EditMode -ErrorAction Stop
    Set-PSReadLineOption `
      -HistoryNoDuplicates:$Settings.HistoryNoDuplicates `
      -ErrorAction Stop

    if (-not [string]::IsNullOrEmpty($Settings.PredictionSource)) {
      Set-PSReadLineOption `
        -PredictionSource $Settings.PredictionSource `
        -ErrorAction Stop
    }

    return $true
  } catch [System.Exception] {
    return $false
  }
}

function global:Register-DotfilesPSReadLineOnIdleAction {
  param(
    [Parameter(Mandatory)]
    [string] $Name,

    [Parameter(Mandatory)]
    [scriptblock] $Action
  )

  if (-not $global:DotfilesPSReadLineOnIdleActions) {
    $global:DotfilesPSReadLineOnIdleActions = [ordered]@{}
  }

  $global:DotfilesPSReadLineOnIdleActions[$Name] = $Action

  if ($global:DotfilesPSReadLineOnIdleRegistered) {
    return $true
  }

  try {
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle `
      -SupportEvent `
      -MaxTriggerCount 1 `
      -Action {
        if ($global:DotfilesPSReadLineOnIdleActions) {
          foreach ($startupAction in @($global:DotfilesPSReadLineOnIdleActions.Values)) {
            try {
              & $startupAction | Out-Null
            } catch [System.Exception] {
              continue
            }
          }

          $global:DotfilesPSReadLineOnIdleActions.Clear()
        }

        $global:DotfilesPSReadLineOnIdleRegistered = $false
      } | Out-Null

    $global:DotfilesPSReadLineOnIdleRegistered = $true
    return $true
  } catch [System.Exception] {
    $global:DotfilesPSReadLineOnIdleRegistered = $false
    return $false
  }
}

function global:Invoke-DotfilesPSReadLineStartupAction {
  param(
    [Parameter(Mandatory)]
    [string] $Name,

    [Parameter(Mandatory)]
    [scriptblock] $Action
  )

  if (-not (Test-DotfilesPSReadLineInteractive)) {
    return $false
  }

  if (-not (Get-DotfilesPSReadLineModule)) {
    return $false
  }

  $applied = $false
  if (Test-DotfilesPSReadLineReady) {
    $applied = [bool](& $Action)
  }

  if ((Test-DotfilesPSReadLineDeferredHost) -or (-not $applied)) {
    Register-DotfilesPSReadLineOnIdleAction `
      -Name $Name `
      -Action ($Action.GetNewClosure()) | Out-Null
  }

  return $applied
}

function global:Initialize-DotfilesPSReadLineOptions {
  $psReadLineModule = Get-DotfilesPSReadLineModule
  if ($null -eq $psReadLineModule) {
    return
  }

  $psReadLineSettings = Get-DotfilesPSReadLineSettings -Module $psReadLineModule
  Invoke-DotfilesPSReadLineStartupAction -Name 'options' -Action {
    Set-DotfilesPSReadLineSettings -Settings $psReadLineSettings
  } | Out-Null
}

if ($env:DOTFILES_TEST_PSREADLINE_SKIP_INIT -ne '1') {
  Initialize-DotfilesPSReadLineOptions
}
