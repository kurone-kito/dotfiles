Set-StrictMode -Version Latest

function Add-Link {
  param(
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [System.IO.FileInfo]
    $Source,

    [Parameter(Mandatory)][string]
    $Destination
  )

  New-Item $Destination -Name $Source.Name -ItemType SymbolicLink `
    -Value $Source.FullName -Force
  <#
  .SYNOPSIS
  Add a symbolic link to a file.
  .PARAMETER Source
  The source file.
  .PARAMETER Destination
  The destination directory.
  #>
}

function Add-Links {
  param(
    [Parameter(Mandatory)][string]
    $Source,

    [Parameter(ValueFromPipeline = $true, Mandatory = $true)][string]
    $Destination
  )

  New-Item -Path $Destination -ItemType Directory -Force
  if (Test-Path $Source) {
    Get-ChildItem -Path $Source -Attributes !Directory `
    | ForEach-Object { $_ | Add-Link -Destination $Destination }
  }
  <#
  .SYNOPSIS
  create the target folder and add all files contained in the folder
  specified as the source to it as symbolic links
  .PARAMETER Source
  The source directory.
  .PARAMETER Destination
  The destination directory.
  #>
}

function Get-IsAdmin {
  $user = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]$user
  $principal.IsInRole('Administrators')
  <#
  .SYNOPSIS
  The function gets whether the current user has privileges.
  .INPUTS
  None.
  .OUTPUTS
  System.Boolean. Whether the current user has privileges.
  #>
}

function Invoke-Self {
  $options = Join-PSOptions $MyInvocation.ScriptName
  Start-Process powershell.exe -ArgumentList $options -Wait
  <#
  .SYNOPSIS
  The function invokes the caller script on the new window.
  .INPUTS
  None.
  #>
}

function Invoke-SelfWithPrivileges {
  if (Get-IsAdmin) {
    return $false
  }
  [Console]::WriteLine('Please elevate to privileges for installing an app')
  $options = Join-PSOptions $MyInvocation.ScriptName
  Start-Process powershell.exe -ArgumentList $options -Wait -Verb RunAs
  return $true
  <#
  .SYNOPSIS
  The function invokes the caller script on the new window with elevate to privileges.
  .INPUTS
  None.
  .OUTPUTS
  System.Boolean. It returns true when it should exit to the caller script.
  Otherwise, returns false.
  #>
}

function Join-PSOptions {
  param (
    [Parameter(Mandatory)][string]
    # Specifies the filename.
    $fileName
  )
  '-ExecutionPolicy Bypass -NoLogo -File "{0}" 1' -f $fileName
  <#
  .SYNOPSIS
  The function gets the options on PowerShell execution.
  .OUTPUTS
  System.String. The options.
  #>
}

Export-ModuleMember -Function Add-Link
Export-ModuleMember -Function Add-Links
Export-ModuleMember -Function Get-IsAdmin
Export-ModuleMember -Function Invoke-Self
Export-ModuleMember -Function Invoke-SelfWithPrivileges
