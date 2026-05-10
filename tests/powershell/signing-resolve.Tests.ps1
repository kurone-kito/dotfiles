# Tests for the SSH-signing schema rendering of git/config.tmpl and
# the per-profile generator templates. Mirrors tests/bash/signing-resolve.bats.
# Skipped when chezmoi is not available on PATH (e.g., minimal Windows runners).

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoHome = Join-Path $PSScriptRoot '..' '..' 'home' | Resolve-Path
  $script:ConfigTmpl = Join-Path $script:RepoHome 'dot_config' 'git' 'config.tmpl'
  $script:ProfilesTmpl = Join-Path $script:RepoHome 'run_onchange_after_generate-git-profiles.ps1.tmpl'

  function Invoke-Render {
    param(
      [string] $TemplatePath,
      [string] $ConfigJson
    )
    $cfg = Join-Path ([IO.Path]::GetTempPath()) ("signing-{0}.json" -f [guid]::NewGuid())
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("signing-{0}-dest" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Set-Content -Path $cfg -Value $ConfigJson -Encoding utf8NoBOM
    try {
      $output = & chezmoi execute-template --file $TemplatePath `
        --config $cfg --config-format json `
        --source $script:RepoHome --destination $dest 2>&1
      [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output -join "`n")
      }
    } finally {
      Remove-Item -Path $cfg, $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe 'signing-resolve' -Skip:(-not $script:HasChezmoi) {

  Context 'git/config.tmpl' {
    It 'no signing config emits no signing blocks' {
      $r = Invoke-Render $script:ConfigTmpl '{ "data": {} }'
      $r.ExitCode | Should -Be 0
      $r.Output   | Should -Not -Match 'signingkey'
      $r.Output   | Should -Not -Match '\[commit\]'
    }

    It 'GPG-only renders legacy GPG signing blocks' {
      $r = Invoke-Render $script:ConfigTmpl '{ "data": { "git": { "signingkey": "DEADBEEF1234" } } }'
      $r.ExitCode | Should -Be 0
      $r.Output   | Should -Match 'signingkey = "DEADBEEF1234"'
      $r.Output   | Should -Match 'gpgsign = if-asked'
      $r.Output   | Should -Not -Match 'format = ssh'
    }

    It 'SSH-only signing_fallback emits ssh format and absolute path key' {
      $json = '{ "data": { "secret": { "ssh": { "keys": { "personal": { "item": "i", "filename": "id_ed25519_personal", "signing_fallback": true } } } } } }'
      $r = Invoke-Render $script:ConfigTmpl $json
      $r.ExitCode | Should -Be 0
      $r.Output   | Should -Match 'format = ssh'
      $r.Output   | Should -Match '/\.ssh/id_ed25519_personal\.pub'
      $r.Output   | Should -Match 'commit-ssh ='
      $r.Output   | Should -Match 'tag-ssh ='
      $r.Output   | Should -Match 'rebase-ssh ='
    }

    It 'GPG fpr + signing_fallback keeps GPG primary, adds SSH aliases' {
      $json = '{ "data": { "git": { "signingkey": "FPR" }, "secret": { "ssh": { "keys": { "p": { "item": "i", "filename": "id", "signing_fallback": true } } } } } }'
      $r = Invoke-Render $script:ConfigTmpl $json
      $r.ExitCode | Should -Be 0
      $r.Output   | Should -Match 'signingkey = "FPR"'
      $r.Output   | Should -Match 'gpgsign = if-asked'
      $r.Output   | Should -Not -Match 'format = ssh'
      $r.Output   | Should -Match 'commit-ssh ='
      $r.Output   | Should -Match '/\.ssh/id\.pub'
    }

    It 'explicit signing_format=ssh forces SSH primary' {
      $json = '{ "data": { "git": { "signingkey": "FPR", "signing_format": "ssh" }, "secret": { "ssh": { "keys": { "p": { "item": "i", "filename": "id", "signing_fallback": true } } } } } }'
      $r = Invoke-Render $script:ConfigTmpl $json
      $r.ExitCode | Should -Be 0
      $r.Output   | Should -Match 'format = ssh'
      $r.Output   | Should -Match '/\.ssh/id\.pub"'
      $r.Output   | Should -Not -Match 'signingkey = "FPR"'
    }

    It 'legacy primary_signing field is rejected with rename hint' {
      $json = '{ "data": { "secret": { "ssh": { "keys": { "p": { "item": "i", "filename": "id", "primary_signing": true } } } } } }'
      $r = Invoke-Render $script:ConfigTmpl $json
      $r.ExitCode | Should -Not -Be 0
      $r.Output   | Should -Match 'primary_signing was renamed to signing_fallback'
    }

    It 'multiple signing_fallback keys fail' {
      $json = '{ "data": { "secret": { "ssh": { "keys": { "a": { "item": "i", "filename": "a", "signing_fallback": true }, "b": { "item": "i", "filename": "b", "signing_fallback": true } } } } } }'
      $r = Invoke-Render $script:ConfigTmpl $json
      $r.ExitCode | Should -Not -Be 0
      $r.Output   | Should -Match 'multiple'
    }

    It 'signing_format=ssh without a fallback key fails' {
      $json = '{ "data": { "git": { "signing_format": "ssh" } } }'
      $r = Invoke-Render $script:ConfigTmpl $json
      $r.ExitCode | Should -Not -Be 0
      $r.Output   | Should -Match 'requires exactly one'
    }

    It 'signing_profiles referencing unknown profile fails' {
      $json = '{ "data": { "secret": { "ssh": { "keys": { "p": { "item": "i", "filename": "id", "signing_profiles": ["nope"] } } } } } }'
      $r = Invoke-Render $script:ConfigTmpl $json
      $r.ExitCode | Should -Not -Be 0
      $r.Output   | Should -Match 'unknown profile'
    }
  }

  Context 'generate-git-profiles.ps1.tmpl' {
    It 'GPG profile + signing_profiles keeps GPG primary, adds SSH aliases' {
      $json = '{ "data": { "git": { "profiles": { "work": { "name": "W", "email": "w@e", "gitdir": "~/w/", "signingkey": "WORKFPR" } } }, "secret": { "ssh": { "keys": { "p": { "item": "i", "filename": "id_work", "signing_profiles": ["work"] } } } } } }'
      $r = Invoke-Render $script:ProfilesTmpl $json
      $r.ExitCode | Should -Be 0
      $r.Output   | Should -Match 'signingkey = "WORKFPR"'
      $r.Output   | Should -Not -Match 'format = ssh'
      $r.Output   | Should -Match 'commit-ssh ='
      $r.Output   | Should -Match '/\.ssh/id_work\.pub'
    }

    It 'SSH-only profile (no GPG signingkey) emits ssh format + aliases' {
      $json = '{ "data": { "git": { "profiles": { "work": { "name": "W", "email": "w@e", "gitdir": "~/w/" } } }, "secret": { "ssh": { "keys": { "p": { "item": "i", "filename": "id_work", "signing_profiles": ["work"] } } } } } }'
      $r = Invoke-Render $script:ProfilesTmpl $json
      $r.ExitCode | Should -Be 0
      $r.Output   | Should -Match 'format = ssh'
      $r.Output   | Should -Match '/\.ssh/id_work\.pub'
      $r.Output   | Should -Match 'commit-ssh ='
    }

    It 'GPG-only profile preserves legacy block (no aliases)' {
      $json = '{ "data": { "git": { "profiles": { "work": { "name": "W", "email": "w@e", "gitdir": "~/w/", "signingkey": "FPR2" } } } } }'
      $r = Invoke-Render $script:ProfilesTmpl $json
      $r.ExitCode | Should -Be 0
      $r.Output   | Should -Match 'signingkey = "FPR2"'
      $r.Output   | Should -Not -Match 'format = ssh'
      $r.Output   | Should -Not -Match 'commit-ssh'
    }
  }
}
