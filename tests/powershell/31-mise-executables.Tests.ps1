# Tests for the PowerShell mise executable resolver (conf.d/31-mise-executables.ps1).
# Exercises: resolution of starship, git-wt, and node through `mise which`, a
# per-tool miss, a reported path that does not exist, a missing mise, and the
# rule that no tool is launched and nothing is exported to the environment.
# A fake mise and stand-in tools log their calls to a file, so no live mise
# is required.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '31-mise-executables.ps1'

  function ConvertTo-SingleQuotedText {
    param([string] $Value)
    return $Value -replace "'", "''"
  }

  # A stand-in tool. Launching it appends a "launched" line to the call log.
  function New-ToolStandIn {
    param([string] $Dir, [string] $Name, [string] $LogPath)
    $path = Join-Path $Dir "$Name.ps1"
    $log = ConvertTo-SingleQuotedText $LogPath
    [System.IO.File]::WriteAllText($path, "Add-Content -LiteralPath '$log' -Value '$Name launched'`n")
    return $path
  }

  # A fake mise that answers `which <tool>` from $Map and logs each call. A
  # $null value makes that call exit 1, as mise does for an unavailable tool.
  function New-FakeMise {
    param([string] $Dir, [hashtable] $Map, [string] $LogPath)
    $cases = foreach ($tool in $Map.Keys) {
      $value = $Map[$tool]
      if ($null -eq $value) {
        "  '$tool' { exit 1 }"
      } else {
        "  '$tool' { Write-Output '$(ConvertTo-SingleQuotedText $value)'; exit 0 }"
      }
    }
    $template = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)
Add-Content -LiteralPath '__LOG__' -Value ('mise ' + ($Arguments -join ' '))
if ($Arguments[0] -ne 'which') { exit 2 }
switch ($Arguments[1]) {
__CASES__
  default { exit 1 }
}
'@
    $body = $template.Replace('__LOG__', (ConvertTo-SingleQuotedText $LogPath)).Replace(
      '__CASES__', ($cases -join "`n"))
    $path = Join-Path $Dir 'mise.ps1'
    [System.IO.File]::WriteAllText($path, $body)
    return $path
  }
}

Describe '31-mise-executables' {

  BeforeEach {
    $script:Dir = Join-Path $TestDrive ('mise-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
    $script:CallLog = Join-Path $script:Dir 'calls.log'
    New-Item -ItemType File -Path $script:CallLog -Force | Out-Null

    $script:StarshipExe = New-ToolStandIn $script:Dir 'starship' $script:CallLog
    $script:GitWtExe = New-ToolStandIn $script:Dir 'git-wt' $script:CallLog
    $script:NodeExe = New-ToolStandIn $script:Dir 'node' $script:CallLog
    $script:FakeMise = New-FakeMise $script:Dir @{
      'starship' = $script:StarshipExe
      'git-wt'   = $script:GitWtExe
      'node'     = $script:NodeExe
    } $script:CallLog

    Mock Get-Command {
      [pscustomobject]@{
        Name        = 'mise'
        CommandType = 'Application'
        Path        = $script:FakeMise
        Source      = $script:FakeMise
      }
    } -ParameterFilter { $Name -eq 'mise' }

    Remove-Variable __miseExecutables -Scope Global -ErrorAction SilentlyContinue
  }

  AfterEach {
    Remove-Variable __miseExecutables -Scope Global -ErrorAction SilentlyContinue
  }

  It 'publishes the path that mise reports for each of the three tools' {
    . $script:Subject

    $__miseExecutables.Count | Should -Be 3
    $__miseExecutables['starship'] | Should -Be $script:StarshipExe
    $__miseExecutables['git-wt'] | Should -Be $script:GitWtExe
    $__miseExecutables['node'] | Should -Be $script:NodeExe
  }

  It 'asks mise once per tool and launches none of the tools' {
    . $script:Subject

    $calls = @(Get-Content -LiteralPath $script:CallLog)
    $calls | Should -Be @(
      'mise which starship'
      'mise which git-wt'
      'mise which node'
    )
    $calls | Where-Object { $_ -like '*launched' } | Should -BeNullOrEmpty
  }

  It 'leaves one tool to PATH lookup when mise fails for it and keeps the others' {
    $script:FakeMise = New-FakeMise $script:Dir @{
      'starship' = $script:StarshipExe
      'git-wt'   = $null
      'node'     = $script:NodeExe
    } $script:CallLog

    . $script:Subject

    $__miseExecutables.ContainsKey('git-wt') | Should -BeFalse
    $__miseExecutables['starship'] | Should -Be $script:StarshipExe
    $__miseExecutables['node'] | Should -Be $script:NodeExe
  }

  It 'leaves a tool out when mise reports a path that does not exist' {
    $script:FakeMise = New-FakeMise $script:Dir @{
      'starship' = $script:StarshipExe
      'git-wt'   = $script:GitWtExe
      'node'     = (Join-Path $script:Dir 'missing-node.exe')
    } $script:CallLog

    . $script:Subject

    $__miseExecutables.ContainsKey('node') | Should -BeFalse
    $__miseExecutables.Count | Should -Be 2
  }

  It 'exports nothing to the environment' {
    $before = @(Get-ChildItem Env: | ForEach-Object { $_.Name } | Sort-Object)

    . $script:Subject

    $after = @(Get-ChildItem Env: | ForEach-Object { $_.Name } | Sort-Object)
    $after | Should -Be $before
  }

  It 'publishes nothing and launches nothing when mise is not on the command path' -Skip:($IsWindows -ne $false) {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mise' }

    . $script:Subject

    $__miseExecutables.Count | Should -Be 0
    Get-Content -LiteralPath $script:CallLog | Should -BeNullOrEmpty
  }
}
