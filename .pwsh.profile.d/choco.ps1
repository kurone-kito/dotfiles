#!/usr/bin/env pwsh

Set-StrictMode -Version Latest

# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = $env:ChocolateyInstall `
| Join-Path -ChildPath helpers `
| Join-Path -ChildPath chocolateyProfile.psm1

if (Test-Path $ChocolateyProfile) {
  Import-Module $ChocolateyProfile
}
