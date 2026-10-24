# Tests for the PowerShell twins of the user-global IDD activation helper
# wrappers (dotfiles issue #676). Each case runs a twin in a child pwsh
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
  $script:UpstreamCommit = '77befdd4030757464bed7f31c7dfe6d0a404a18b'
}

Describe 'user-global IDD activation helper twins' {
  It '<_> invokes the v0.17.0 release commit' -ForEach $script:Twins {
    $helper = ($_ -replace '^executable_', '') -replace '\.ps1$', ''
    $wrapper = Join-Path $script:BinDir $_
    $invocationLines = @(Get-Content -LiteralPath $wrapper | Where-Object { $_ -match '^& npx --yes --package ' })
    $invocationLines.Count | Should -Be 1
    $expectedInvocation = "& npx --yes --package 'https://codeload.github.com/kurone-kito/idd-skill/tar.gz/$script:UpstreamCommit' $helper @args"
    $invocationLines[0] | Should -BeExactly $expectedInvocation
  }

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

  It '<_> forwards helper arguments to npx and returns its exit status' -ForEach $script:Twins {
    $helper = ($_ -replace '^executable_', '') -replace '\.ps1$', ''
    $wrapper = Join-Path $script:BinDir $_
    $fakeDir = Join-Path ([IO.Path]::GetTempPath()) ('idd-fake-npx-' + [guid]::NewGuid().ToString('N'))
    $captureFile = Join-Path $fakeDir 'args.txt'
    New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
    if ($env:OS -eq 'Windows_NT') {
      $fakeNpx = @(
        '@echo off'
        '>"%IDD_TEST_NPX_ARGS%" echo %*'
        'exit /b 23'
      ) -join "`r`n"
      Set-Content -LiteralPath (Join-Path $fakeDir 'npx.cmd') -Value $fakeNpx -Encoding ASCII
      Set-Content -LiteralPath (Join-Path $fakeDir 'node.cmd') -Value '@exit /b 0' -Encoding ASCII
    } else {
      $fakeNpx = @'
#!/bin/sh
printf '%s\n' "$@" > "$IDD_TEST_NPX_ARGS"
exit 23
'@
      Set-Content -LiteralPath (Join-Path $fakeDir 'npx') -Value $fakeNpx -Encoding ASCII
      & chmod +x (Join-Path $fakeDir 'npx')
      Set-Content -LiteralPath (Join-Path $fakeDir 'node') -Value "#!/bin/sh`nexit 0`n" -Encoding ASCII
      & chmod +x (Join-Path $fakeDir 'node')
    }

    $originalPath = $env:PATH
    $originalCapture = $env:IDD_TEST_NPX_ARGS
    $originalPreference = $ErrorActionPreference
    try {
      $env:IDD_TEST_NPX_ARGS = $captureFile
      $env:PATH = "$fakeDir$([IO.Path]::PathSeparator)$originalPath"
      $ErrorActionPreference = 'Continue'
      $output = & $script:PwshExe -NoProfile -File $wrapper --probe-arg example 2>&1
      $exitCode = $LASTEXITCODE
      $capturedArgs = (Get-Content -LiteralPath $captureFile -Raw -ErrorAction SilentlyContinue) -replace '\r?\n', ' '
    } finally {
      $env:PATH = $originalPath
      $env:IDD_TEST_NPX_ARGS = $originalCapture
      $ErrorActionPreference = $originalPreference
      Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $exitCode | Should -Be 23
    $capturedArgs | Should -Not -BeNullOrEmpty
    $capturedArgs | Should -Match ([regex]::Escape("$helper --probe-arg example"))
    $capturedArgs | Should -Match ([regex]::Escape($script:UpstreamCommit))
  }

  It 'the Node.js floor probe accepts 22.23.2, 24.2.0 and 26 and rejects the boundaries below' {
    Get-Command node -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because 'node is needed to evaluate the floor probe'
    foreach ($twin in $script:Twins) {
      # Take the probe from the twin itself, so the test checks the shipped expression.
      $line = Get-Content -LiteralPath (Join-Path $script:BinDir $twin) | Where-Object { $_ -match '^& node -e ".*" 2>\$null$' } | Select-Object -First 1
      $line | Should -Not -BeNullOrEmpty -Because "$twin must carry the floor probe"
      $js = [regex]::Match($line, '^& node -e "(.*)" 2>\$null$').Groups[1].Value
      foreach ($version in @('22.23.2', '22.23.3', '24.2.0', '24.21.0', '26.0.0')) {
        $probe = $js.Replace('process.versions.node', "'$version'")
        & node -e $probe 2>$null
        $LASTEXITCODE | Should -Be 0 -Because "$twin accepts Node $version"
      }
      foreach ($version in @('22.23.1', '22.18.0', '23.11.0', '24.1.9', '25.0.0', '20.11.0')) {
        $probe = $js.Replace('process.versions.node', "'$version'")
        & node -e $probe 2>$null
        $LASTEXITCODE | Should -Be 1 -Because "$twin rejects Node $version"
      }
    }
  }

  It 'the <_>.cmd launcher forwards the twin exit status when npx is missing' -ForEach @('idd-activation', 'idd-effective-config') -Skip:($env:OS -ne 'Windows_NT') {
    $helper = $_
    # The launcher finds its twin by the deployed name, so stage both files
    # under their deployed names (chezmoi drops the executable_ prefix).
    $stageDir = Join-Path ([IO.Path]::GetTempPath()) ('idd-cmd-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:BinDir "executable_$helper.cmd") -Destination (Join-Path $stageDir "$helper.cmd")
    Copy-Item -LiteralPath (Join-Path $script:BinDir "executable_$helper.ps1") -Destination (Join-Path $stageDir "$helper.ps1")
    $launcher = Join-Path $stageDir "$helper.cmd"
    # System32 keeps where.exe, and the Windows PowerShell directory keeps
    # powershell.exe. Neither pwsh nor npx is on this PATH, so the twin's
    # npx guard answers, and the launcher must pass its exit status through.
    $systemDir = Join-Path $env:SystemRoot 'System32'
    $psDir = Join-Path $systemDir 'WindowsPowerShell\v1.0'
    $originalPath = $env:PATH
    $originalPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $env:PATH = "$systemDir;$psDir"
      $output = & cmd.exe /d /c $launcher 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      $env:PATH = $originalPath
      $ErrorActionPreference = $originalPreference
      Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $exitCode | Should -Be 1
    ($output | Out-String) | Should -Match 'npx is required'
  }

  It 'the <_>.cmd launcher dispatches arguments and the pinned release through its PowerShell twin' -ForEach @('idd-activation', 'idd-effective-config') -Skip:($env:OS -ne 'Windows_NT') {
    $helper = $_
    $stageDir = Join-Path ([IO.Path]::GetTempPath()) ('idd-cmd-args-' + [guid]::NewGuid().ToString('N'))
    $fakeDir = Join-Path $stageDir 'bin'
    New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:BinDir "executable_$helper.cmd") -Destination (Join-Path $stageDir "$helper.cmd")
    Copy-Item -LiteralPath (Join-Path $script:BinDir "executable_$helper.ps1") -Destination (Join-Path $stageDir "$helper.ps1")
    $captureFile = Join-Path $stageDir 'args.txt'
    $fakeNpx = @(
      '@echo off'
      '>"%IDD_TEST_NPX_ARGS%" echo %*'
      'exit /b 23'
    ) -join "`r`n"
    Set-Content -LiteralPath (Join-Path $fakeDir 'npx.cmd') -Value $fakeNpx -Encoding ASCII
    # The PowerShell twin probes Node before invoking npx; keep that probe passing.
    Set-Content -LiteralPath (Join-Path $fakeDir 'node.cmd') -Value '@exit /b 0' -Encoding ASCII
    $systemDir = Join-Path $env:SystemRoot 'System32'
    $psDir = Join-Path $systemDir 'WindowsPowerShell\v1.0'
    $originalPath = $env:PATH
    $originalCapture = $env:IDD_TEST_NPX_ARGS
    $originalPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $env:IDD_TEST_NPX_ARGS = $captureFile
      $env:PATH = "$fakeDir;$systemDir;$psDir"
      $launcher = Join-Path $stageDir "$helper.cmd"
      $commandLine = "`"$launcher`" --probe-arg example"
      $output = & cmd.exe /d /c $commandLine 2>&1
      $exitCode = $LASTEXITCODE
      $capturedArgs = (Get-Content -LiteralPath $captureFile -Raw -ErrorAction SilentlyContinue) -replace '\r?\n', ' '
    } finally {
      $env:PATH = $originalPath
      $env:IDD_TEST_NPX_ARGS = $originalCapture
      $ErrorActionPreference = $originalPreference
      Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $exitCode | Should -Be 23
    $capturedArgs | Should -Match ([regex]::Escape("$helper --probe-arg example"))
    $capturedArgs | Should -Match ([regex]::Escape($script:UpstreamCommit))
  }
}
