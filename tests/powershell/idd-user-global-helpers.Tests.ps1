# Tests for the PowerShell twins of the user-global IDD activation helper
# wrappers (dotfiles issue #646). Each case runs a twin in a child pwsh
# whose PATH holds neither npx nor node, so the fail-loud guard answers
# without any network access. Argument forwarding and the upstream JSON
# output need npx; the bats runtime cases cover those on Linux.

BeforeDiscovery {
  $script:Twins = @(
    'executable_idd-activation.ps1'
    'executable_idd-effective-config.ps1'
  )
}

BeforeAll {
  $script:BinDir = Join-Path $PSScriptRoot '../../home/dot_local/bin'
  $script:PwshExe = (Get-Process -Id $PID).Path
}

Describe 'user-global IDD activation helper twins' {
  It '<_> exits 1 with a message when npx is not on PATH' -ForEach $script:Twins {
    $wrapper = Join-Path $script:BinDir $_
    $emptyDir = Join-Path ([IO.Path]::GetTempPath()) ('idd-no-npx-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
    $originalPath = $env:PATH
    $originalPreference = $ErrorActionPreference
    try {
      # Windows PowerShell 5.1 turns a native command's stderr into a
      # terminating error under 2>&1 when the preference is Stop, which
      # would throw before the exit code is read. Run the child with Continue.
      $ErrorActionPreference = 'Continue'
      $env:PATH = $emptyDir
      $output = & $script:PwshExe -NoProfile -File $wrapper 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      $env:PATH = $originalPath
      $ErrorActionPreference = $originalPreference
      Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $exitCode | Should -Be 1
    ($output | Out-String) | Should -Match 'npx is required'
  }

  It '<_> fails loudly when Node.js is below the upstream floor' -ForEach $script:Twins {
    $wrapper = Join-Path $script:BinDir $_
    $fakeDir = Join-Path ([IO.Path]::GetTempPath()) ('idd-old-node-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
    # A fake npx passes the first guard. A fake node fails the floor probe,
    # so only the Node.js floor guard can answer.
    if ($env:OS -eq 'Windows_NT') {
      Set-Content -LiteralPath (Join-Path $fakeDir 'node.cmd') -Value "@exit /b 1`r`n" -Encoding ASCII
      Set-Content -LiteralPath (Join-Path $fakeDir 'npx.cmd') -Value "@exit /b 0`r`n" -Encoding ASCII
    } else {
      Set-Content -LiteralPath (Join-Path $fakeDir 'node') -Value "#!/bin/sh`nexit 1`n" -Encoding ASCII
      Set-Content -LiteralPath (Join-Path $fakeDir 'npx') -Value "#!/bin/sh`nexit 0`n" -Encoding ASCII
      & chmod +x (Join-Path $fakeDir 'node') (Join-Path $fakeDir 'npx')
    }
    $originalPath = $env:PATH
    $originalPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $env:PATH = $fakeDir
      $output = & $script:PwshExe -NoProfile -File $wrapper 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      $env:PATH = $originalPath
      $ErrorActionPreference = $originalPreference
      Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $exitCode | Should -Be 1
    ($output | Out-String) | Should -Match 'needs Node.js 22.23.2\+, 24.2.0\+, or 26\+'
  }
}
