# Tests for the PowerShell coderabbit-authoring-review script, the IDD
# issue-authoring draft reviewer. The Unix-scoped cases run the script as a
# subprocess under pwsh with a stub `coderabbit` on PATH, so no live CodeRabbit
# account is needed. Windows-only behaviour is checked by the Windows jobs; the
# .cmd forwarder is checked statically here on every host.

BeforeAll {
  $script:Subject = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_coderabbit-authoring-review.ps1'
  $script:Forwarder = Join-Path $PSScriptRoot `
    '../../home/dot_local/bin/executable_coderabbit-authoring-review.cmd'
  $script:PwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
  if (-not $script:PwshPath) {
    $script:PwshPath = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
  }

  $script:GoodDraft = '{"title":"Add the draft reviewer","body":"Body text.","packet":' +
    '{"goal":"Ship it.","constraints":["No live calls"],"evidence":[],' +
    '"relationships":["Refs #657"],"checklist":["Lint passes"]}}'

  # Runs the script with the given stdin text and extra arguments. The stdin
  # text is written to a UTF-8 file without a byte-order mark and redirected,
  # so the bytes the script reads never depend on the pipeline's encoding.
  # Returns stdout (without its final newline), stderr and the exit code.
  function script:Invoke-Subject {
    param([string]$StdinText, [string[]]$Arguments = @())
    $token = [guid]::NewGuid().ToString('N')
    $tempDir = [IO.Path]::GetTempPath()
    $inPath = Join-Path $tempDir ('cra-in.' + $token)
    $outPath = Join-Path $tempDir ('cra-out.' + $token)
    $errPath = Join-Path $tempDir ('cra-err.' + $token)
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($inPath, $StdinText, $utf8)
    try {
      $allArguments = @('-NoProfile', '-File', $script:Subject) + $Arguments
      $process = Start-Process -FilePath $script:PwshPath -ArgumentList $allArguments `
        -RedirectStandardInput $inPath -RedirectStandardOutput $outPath `
        -RedirectStandardError $errPath -NoNewWindow -Wait -PassThru
      $outText = if (Test-Path -LiteralPath $outPath) { [IO.File]::ReadAllText($outPath) } else { '' }
      $errText = if (Test-Path -LiteralPath $errPath) { [IO.File]::ReadAllText($errPath) } else { '' }
      return [pscustomobject]@{
        Out  = ($outText -replace "\r?\n\z", '')
        Err  = [string]$errText
        Code = $process.ExitCode
      }
    } finally {
      foreach ($path in $inPath, $outPath, $errPath) {
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
      }
    }
  }
}

Describe 'coderabbit-authoring-review arguments' -Skip:($IsWindows -ne $false) {
  It 'prints the usage line on stdout for --help and exits 0' {
    $result = Invoke-Subject -StdinText '' -Arguments @('--help')
    $result.Code | Should -Be 0
    $result.Out | Should -Be 'Usage: coderabbit-authoring-review'
  }

  It 'exits 2 for any other argument' {
    $result = Invoke-Subject -StdinText '' -Arguments @('--bogus')
    $result.Code | Should -Be 2
  }
}

Describe 'coderabbit-authoring-review stdin' -Skip:($IsWindows -ne $false) {
  It 'fails with empty stdout for input that is not the expected draft shape' {
    foreach ($input in @(
        '',
        'not json',
        '{"title":"T"}',
        '{"title":"","body":"B","packet":{"goal":"G","constraints":[],"evidence":[],"relationships":[],"checklist":[]}}',
        '{"title":"T","body":"B","packet":{"goal":"G","constraints":[],"evidence":[],"relationships":[]}}'
      )) {
      $result = Invoke-Subject -StdinText $input
      $result.Code | Should -Not -Be 0
      $result.Out | Should -Be ''
    }
  }
}

Describe 'coderabbit-authoring-review review run' -Skip:($IsWindows -ne $false) {
  BeforeEach {
    $script:StubDir = Join-Path ([IO.Path]::GetTempPath()) ('cra-stub.' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:StubDir | Out-Null
    $stub = Join-Path $script:StubDir 'coderabbit'
    @'
#!/bin/sh
case "$1 $2" in
  'auth status') printf '{"authenticated": true}\n'; exit 0 ;;
  'review --agent')
    if [ "${STUB_MODE:-ok}" = fail ]; then printf 'partial\n'; exit 3; fi
    printf 'REVIEW OK\n'; exit 0 ;;
esac
exit 9
'@ | Set-Content -LiteralPath $stub -NoNewline
    & chmod +x $stub
    $script:SavedPath = $env:PATH
    $env:PATH = $script:StubDir + [IO.Path]::PathSeparator + $env:PATH
    $script:SavedEnv = @{}
    foreach ($name in 'CODERABBIT_CRITIQUE_DEEP', 'CODERABBIT_CRITIQUE_TIMEOUT', 'TMPDIR', 'TEMP', 'TMP') {
      $script:SavedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
      Remove-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue
    }
    # The launcher refuses a temporary directory inside the checkout. Another
    # test file may leave the temp variables pointing into the repository, so
    # pin them to a directory outside it for these cases.
    $isolatedTemp = if ($IsWindows) { Join-Path ([IO.Path]::GetTempPath()) 'cra-authoring-tests' } else { '/tmp/cra-authoring-tests' }
    New-Item -ItemType Directory -Path $isolatedTemp -Force | Out-Null
    $env:TMPDIR = $isolatedTemp
    $env:TEMP = $isolatedTemp
    $env:TMP = $isolatedTemp
  }

  AfterEach {
    foreach ($name in $script:SavedEnv.Keys) {
      [Environment]::SetEnvironmentVariable($name, $script:SavedEnv[$name])
    }
    $env:PATH = $script:SavedPath
    Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  It 'returns the review text and exits 0 for a valid draft' {
    $result = Invoke-Subject -StdinText $script:GoodDraft
    $result.Code | Should -Be 0 -Because $result.Err
    $result.Out | Should -Be 'REVIEW OK'
  }

  It 'passes through a non-zero review exit status with empty stdout' {
    $env:STUB_MODE = 'fail'
    try {
      $result = Invoke-Subject -StdinText $script:GoodDraft
      $result.Code | Should -Be 3 -Because $result.Err
      $result.Out | Should -Be ''
    } finally {
      Remove-Item Env:STUB_MODE -ErrorAction SilentlyContinue
    }
  }

  It 'fails closed with empty stdout when coderabbit is not on PATH' {
    $env:PATH = (Join-Path $script:StubDir 'missing')
    $result = Invoke-Subject -StdinText $script:GoodDraft
    $result.Code | Should -Not -Be 0
    $result.Out | Should -Be ''
  }
}

Describe 'coderabbit-authoring-review forwarder (static, every host)' {
  It 'forwards to the .ps1 twin in the same directory with pwsh and powershell fallbacks' {
    $text = Get-Content -LiteralPath $script:Forwarder -Raw
    $text | Should -Match 'coderabbit-authoring-review\.ps1'
    $text | Should -Match 'where pwsh'
    $text | Should -Match 'where powershell'
    $text | Should -Match 'exit /b %ERRORLEVEL%'
  }

  It 'uses LF line endings, as the rest of the repository does' {
    $bytes = [IO.File]::ReadAllBytes($script:Forwarder)
    ($bytes | Where-Object { $_ -eq 13 }).Count | Should -Be 0
  }
}
