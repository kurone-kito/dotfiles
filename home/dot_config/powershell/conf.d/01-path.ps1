# Prepend known tool directories to PATH when they exist on disk.
# Compensates for MSI installers that fail to register their
# install directory in the User or Machine PATH.

$extraPaths = @(
  (Join-Path $env:LOCALAPPDATA 'Zellij')
)

foreach ($dir in $extraPaths) {
  if ((Test-Path $dir) -and ($env:PATH -split ';' -notcontains $dir)) {
    $env:PATH = "$dir;$env:PATH"
  }
}
