# Default Node.js address-selection budget for slow dual-stack connections.
# Mirrors home/dot_config/shell/conf.d/65-node-options.sh; read the header
# there for the reasoning (#588) and the caveats.
#
# Exports --network-family-autoselection-attempt-timeout=2000 through
# NODE_OPTIONS for every Node.js tool, including bw, but only when a node
# that accepts the option is on PATH and NODE_OPTIONS does not already name
# the exact option. Existing content is kept as is and the default is
# appended after it. Anything unexpected (no node, a node that rejects the
# option, a malformed value) leaves the environment untouched and quiet.
#
# Runs after 30-mise.ps1 so the probe sees the node that mise puts on PATH.
# The whole script runs in a child scope so nothing but NODE_OPTIONS leaks
# into the profile. It is PowerShell 5.1 and 7 compatible: no ternary, no
# null-coalescing, no pipeline chain operators.

& {
  $optionName = 'network-family-autoselection-attempt-timeout'
  $defaultOption = "--$optionName=2000"

  # Split NODE_OPTIONS the way Node.js does: only a space separates tokens,
  # a double quote toggles quoting, and a backslash escapes the next
  # character inside quotes. Returns $null for an unterminated quote or an
  # escape at the end, which Node.js rejects.
  function Split-NodeOptions {
    param([string] $Value)

    $tokens = New-Object 'System.Collections.Generic.List[string]'
    $current = New-Object System.Text.StringBuilder
    $quoted = $false
    $haveToken = $false
    $chars = $Value.ToCharArray()

    for ($i = 0; $i -lt $chars.Length; $i++) {
      $c = [string]$chars[$i]
      if ($c -ceq '\' -and $quoted) {
        if ($i -eq $chars.Length - 1) {
          return $null
        }
        $i++
        $c = [string]$chars[$i]
      } elseif ($c -ceq ' ' -and -not $quoted) {
        if ($haveToken) {
          $tokens.Add($current.ToString())
          [void]$current.Clear()
          $haveToken = $false
        }
        continue
      } elseif ($c -ceq '"') {
        $quoted = -not $quoted
        continue
      }
      [void]$current.Append($c)
      $haveToken = $true
    }

    if ($quoted) {
      return $null
    }
    if ($haveToken) {
      $tokens.Add($current.ToString())
    }
    return , $tokens.ToArray()
  }

  # True when the token is the exact option: `--` then the name with `_`
  # and `-` interchangeable, up to an optional `=`. Node.js option names
  # are case-sensitive, hence -ceq.
  function Test-NodeOptionToken {
    param([string] $Token)

    if (-not $Token.StartsWith('--')) {
      return $false
    }
    $name = $Token.Substring(2)
    $equals = $name.IndexOf('=')
    if ($equals -ge 0) {
      $name = $name.Substring(0, $equals)
    }
    return ($name.Replace('_', '-') -ceq $optionName)
  }

  # Application only, like 45-worktrunk.ps1: a function or alias named node
  # must never be run by this script.
  $nodeCommand = Get-Command node -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $nodeCommand) {
    return
  }
  $nodePath = if ($nodeCommand.Path) { $nodeCommand.Path } else { $nodeCommand.Source }
  if ([string]::IsNullOrEmpty($nodePath)) {
    return
  }

  $existing = [Environment]::GetEnvironmentVariable('NODE_OPTIONS')
  if (-not [string]::IsNullOrEmpty($existing)) {
    $tokens = Split-NodeOptions -Value $existing
    if ($null -eq $tokens) {
      return
    }
    foreach ($token in $tokens) {
      if (Test-NodeOptionToken -Token $token) {
        return
      }
    }
  }

  # Probe with only the option set, and with mise auto-install and network
  # access off so a mise shim cannot install anything. The script argument
  # is non-empty because Windows PowerShell 5.1 drops an empty-string
  # argument. Every variable touched is restored, removed if it was absent.
  $probeVariables = [ordered]@{
    NODE_OPTIONS           = $defaultOption
    MISE_AUTO_INSTALL      = '0'
    MISE_EXEC_AUTO_INSTALL = '0'
    MISE_OFFLINE           = '1'
  }
  $saved = @{}
  foreach ($name in $probeVariables.Keys) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
  }
  $savedExitCode = $global:LASTEXITCODE
  $savedPreference = $ErrorActionPreference
  $accepted = $false
  try {
    $ErrorActionPreference = 'SilentlyContinue'
    foreach ($name in $probeVariables.Keys) {
      [Environment]::SetEnvironmentVariable($name, $probeVariables[$name])
    }
    & $nodePath -e 0 2>$null | Out-Null
    $accepted = ($LASTEXITCODE -eq 0)
  } catch {
    $accepted = $false
  } finally {
    foreach ($name in $probeVariables.Keys) {
      [Environment]::SetEnvironmentVariable($name, $saved[$name])
    }
    $global:LASTEXITCODE = $savedExitCode
    $ErrorActionPreference = $savedPreference
  }

  if (-not $accepted) {
    return
  }

  if ([string]::IsNullOrEmpty($existing)) {
    $env:NODE_OPTIONS = $defaultOption
  } else {
    $env:NODE_OPTIONS = "$existing $defaultOption"
  }
}
