#!/usr/bin/env pwsh
# Pre-rendered test fixture for run_onchange_after_55-setup-editors.ps1.tmpl.
# Hash comments are replaced with dummy values since tests don't use chezmoi.
#
# This script is intentionally NOT a chezmoi template.
# It simulates what chezmoi would render with fixed hash values.
#
# vimrc hash: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
# nvim init hash: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
# nvim plugins hash:
#   colorscheme.lua: 0000000000000000000000000000000000000000000000000000000000000001
#   completion.lua: 0000000000000000000000000000000000000000000000000000000000000002
$ErrorActionPreference = 'Continue'

$foundEditor = $false

# ---------------------------------------------------------------------------
# vim — vim-plug
# ---------------------------------------------------------------------------
$vimCmd = Get-Command vim -ErrorAction SilentlyContinue
if ($vimCmd) {
  $foundEditor = $true
  Write-Host 'Setting up vim plugins...'

  # Bootstrap vim-plug if missing (mirrors the auto-bootstrap in .vimrc)
  if ($IsWindows -ne $false) {
    # Windows (including PS5 where $IsWindows is $null)
    $plugVim = Join-Path (Join-Path $HOME 'vimfiles') 'autoload\plug.vim'
  } else {
    $plugVim = Join-Path (Join-Path $HOME '.vim') 'autoload/plug.vim'
  }

  if (-not (Test-Path $plugVim)) {
    $curlCmd = Get-Command curl -ErrorAction SilentlyContinue
    if ($curlCmd) {
      Write-Host '  Bootstrapping vim-plug...'
      $plugDir = Split-Path $plugVim -Parent
      if (-not (Test-Path $plugDir)) {
        New-Item -ItemType Directory -Path $plugDir -Force | Out-Null
      }
      try {
        & curl -fLo $plugVim --create-dirs `
          'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' 2>&1
      } catch {
        Write-Host "  WARNING: vim-plug bootstrap failed; skipping vim."
      }
    } else {
      Write-Host '  WARNING: curl not found; cannot bootstrap vim-plug. Skipping vim.'
    }
  }

  if (Test-Path $plugVim) {
    & vim -es -u (Join-Path $HOME '.vimrc') `
      -c 'PlugInstall --sync' `
      -c 'PlugClean!' `
      -c 'qa!' 2>&1
    if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -eq 0) {
      Write-Host '  vim plugin sync complete.'
    } else {
      Write-Host '  WARNING: vim plugin sync reported errors.'
    }
  }
} else {
  Write-Host 'vim not found; skipping vim plugin setup.'
}

# ---------------------------------------------------------------------------
# nvim — lazy.nvim
# ---------------------------------------------------------------------------
$nvimCmd = Get-Command nvim -ErrorAction SilentlyContinue
if ($nvimCmd) {
  $foundEditor = $true
  Write-Host 'Setting up nvim plugins...'

  # Phase 1: Bootstrap — let init.lua clone lazy.nvim on first run.
  # A separate invocation ensures the Lazy command is registered in a
  # clean session for phase 2.
  & nvim --headless +qa 2>&1

  $lazydir = if ($env:XDG_DATA_HOME) {
    Join-Path $env:XDG_DATA_HOME (Join-Path 'nvim' (Join-Path 'lazy' 'lazy.nvim'))
  } else {
    Join-Path $HOME (Join-Path '.local' (Join-Path 'share' (Join-Path 'nvim' (Join-Path 'lazy' 'lazy.nvim'))))
  }
  if (-not (Test-Path $lazydir)) {
    Write-Host '  WARNING: lazy.nvim bootstrap failed; skipping nvim plugin sync.'
  } else {
    # Phase 2: Sync plugins — Lazy command available from fresh session
    & nvim --headless '+Lazy! sync' +qa 2>&1
    if ($null -eq $LASTEXITCODE -or $LASTEXITCODE -eq 0) {
      Write-Host '  nvim plugin sync complete.'
    } else {
      Write-Host '  WARNING: nvim plugin sync reported errors.'
    }
  }
} else {
  Write-Host 'nvim not found; skipping nvim plugin setup.'
}

if (-not $foundEditor) {
  Write-Host 'No editors found; skipping editor plugin setup.'
}
