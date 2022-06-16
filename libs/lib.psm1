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

Export-ModuleMember -Function Add-Link
Export-ModuleMember -Function Add-Links
