# Tests for the go-template rendering of
# winget-user-path-packages.json.tmpl (the repo-shipped defaults for
# data.wingetUserPath.packages, see docs/winget-user-path.md). Renders
# the real template via chezmoi execute-template (mirrors
# tests/powershell/signing-resolve.Tests.ps1), so the shipped
# defaults and the documented per-field merge behavior get real
# rendering coverage instead of a hand-copied fixture.
#
# .chezmoi.toml.tmpl carries the identical
# `merge (dig "wingetUserPath" "packages" dict .) $wingetDefaultPackages`
# expression (see its own comment: "keep both in sync"), but cannot be
# rendered here: it calls promptStringOnce, a template function that
# only exists inside `chezmoi init`, not `chezmoi execute-template`.
# This file's coverage of the shared merge semantics is representative
# evidence for both files; .chezmoi.toml.tmpl's own content is a
# mirrored single dict-entry addition, verified by code review.
#
# Skipped when chezmoi is not available on PATH (e.g., minimal Windows
# runners).

BeforeDiscovery {
  $script:HasChezmoi = [bool] (Get-Command chezmoi -ErrorAction SilentlyContinue)
}

BeforeAll {
  $script:RepoHome = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home' | Resolve-Path
  $script:ManifestTmpl = Join-Path (
    Join-Path (Join-Path $script:RepoHome 'dot_config') (Join-Path 'powershell' 'lib')
  ) 'winget-user-path-packages.json.tmpl'

  function Invoke-Render {
    param(
      [string] $TemplatePath,
      [string] $ConfigJson
    )
    $cfg = Join-Path ([IO.Path]::GetTempPath()) ("winget-defaults-{0}.json" -f [guid]::NewGuid())
    $dest = Join-Path ([IO.Path]::GetTempPath()) ("winget-defaults-{0}-dest" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    [System.IO.File]::WriteAllText($cfg, $ConfigJson, [System.Text.UTF8Encoding]::new($false))
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

Describe 'winget-user-path-packages.json.tmpl' -Skip:(-not $script:HasChezmoi) {

  Context 'shipped defaults (no user declarations)' {
    BeforeAll {
      $script:Render = Invoke-Render $script:ManifestTmpl '{ "data": {} }'
      $script:Parsed = $script:Render.Output | ConvertFrom-Json
    }

    It 'renders successfully' {
      $script:Render.ExitCode | Should -Be 0
    }

    It 'ships exactly two default entries: mise and chezmoi' {
      $script:Parsed.Count | Should -Be 2
      ($script:Parsed.label | Sort-Object) | Should -Be @('chezmoi', 'mise')
    }

    It 'the chezmoi default has id twpayne.chezmoi, no bin, and is enabled' {
      $chezmoi = $script:Parsed | Where-Object { $_.label -eq 'chezmoi' }
      $chezmoi.id | Should -Be 'twpayne.chezmoi'
      $chezmoi.bin | Should -Be ''
      $chezmoi.enabled | Should -BeTrue
    }

    It 'the mise default is unchanged (id jdx.mise, bin mise/bin)' {
      $mise = $script:Parsed | Where-Object { $_.label -eq 'mise' }
      $mise.id | Should -Be 'jdx.mise'
      $mise.bin | Should -Be 'mise/bin'
      $mise.enabled | Should -BeTrue
    }

    It 'produces the exact deterministic JSON reused as the managed-paths-parity fixture' {
      # This literal string is intentionally duplicated as the
      # DOTFILES_TEST_WINGET_USER_PATH_MANIFEST fixture in
      # tests/powershell/managed-paths-parity.Tests.ps1's "declares the
      # twpayne.chezmoi default" case, so that test exercises the
      # actual rendered-manifest shape rather than an independently
      # hand-written one. Keep both in sync if this ever changes.
      $script:Render.Output | Should -Be (
        '[{"bin":"","enabled":true,"id":"twpayne.chezmoi","label":"chezmoi"},' +
        '{"bin":"mise/bin","enabled":true,"id":"jdx.mise","label":"mise"}]'
      )
    }
  }

  Context 'user-declared override merge behavior on the chezmoi label' {
    It 'enabled = false disables it without needing to restate id' {
      $json = '{ "data": { "wingetUserPath": { "packages": { "chezmoi": { "enabled": false } } } } }'
      $r = Invoke-Render $script:ManifestTmpl $json
      $r.ExitCode | Should -Be 0
      $parsed = $r.Output | ConvertFrom-Json
      $chezmoi = $parsed | Where-Object { $_.label -eq 'chezmoi' }
      $chezmoi.id | Should -Be 'twpayne.chezmoi'
      $chezmoi.enabled | Should -BeFalse
    }

    It 'a declared id/bin overrides the shipped default field-by-field' {
      $json = '{ "data": { "wingetUserPath": { "packages": { "chezmoi": { "id": "Some.Fork", "bin": "sub" } } } } }'
      $r = Invoke-Render $script:ManifestTmpl $json
      $r.ExitCode | Should -Be 0
      $parsed = $r.Output | ConvertFrom-Json
      $chezmoi = $parsed | Where-Object { $_.label -eq 'chezmoi' }
      $chezmoi.id | Should -Be 'Some.Fork'
      $chezmoi.bin | Should -Be 'sub'
      $chezmoi.enabled | Should -BeTrue
    }
  }
}
