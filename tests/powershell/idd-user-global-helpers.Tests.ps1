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
    try {
      $env:PATH = $emptyDir
      $output = & $script:PwshExe -NoProfile -File $wrapper 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      $env:PATH = $originalPath
      Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $exitCode | Should -Be 1
    ($output | Out-String) | Should -Match 'npx is required'
  }
}
