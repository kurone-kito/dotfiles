# VS Code Integrated Terminal

This dotfiles profile is designed to work seamlessly with VS Code's
integrated terminal. The profile loads automatically and includes
VS Code-specific optimizations.

## How it works

The chezmoi profile linker (`run_onchange_after_link-powershell-profile`)
creates `Microsoft.VSCode_profile.ps1` shims at all standard PowerShell
profile locations. These shims source the main profile at
`~/.config/powershell/profile.ps1`.

### VS Code-aware behavior

The profile detects VS Code's integrated terminal via the
`TERM_PROGRAM` environment variable and adjusts behavior:

- **fzf chord bindings** (`Ctrl+t`, `Ctrl+r`): Disabled in VS Code
  terminals because VS Code provides its own keybindings for file
  search and history navigation. The `PSFzf` module is still imported,
  so commands like `Invoke-FuzzyHistory` remain available.
- **Shell integration**: If VS Code's automatic shell integration is
  not active, the profile attempts to load it manually after Starship
  and zoxide initialization to prevent prompt handler conflicts.

### Features available in VS Code terminal

All profile features load in VS Code's integrated terminal:

| Feature    | Status | Notes                             |
| ---------- | :----: | --------------------------------- |
| Starship   |   ✅    | Full prompt with transient prompt |
| zoxide     |   ✅    | `z` directory jumps               |
| mise       |   ✅    | Runtime version management        |
| aliases    |   ✅    | `ll`, `which`, etc.               |
| GPG cache  |   ✅    | Signing commits without pinentry  |
| fzf        |   ✅    | Module imported, chords disabled  |
| worktrunk  |   ✅    | `git-wt` worktree management      |
| PSReadLine |   ✅    | Emacs mode, history, prediction   |
| thefuck    |   ✅    | Command correction                |

## Recommended VS Code settings

Add these to your VS Code **user** settings (`settings.json`) for the
best experience:

### Windows

```jsonc
{
  // Use PowerShell 7 (pwsh) as the default terminal
  "terminal.integrated.defaultProfile.windows": "PowerShell",
  "terminal.integrated.profiles.windows": {
    "PowerShell": {
      "source": "PowerShell",
      "icon": "terminal-powershell"
    }
  },
  // Allow the profile to load (default, but verify it's not disabled)
  "terminal.integrated.shellIntegration.enabled": true
}
```

### Linux / macOS

```jsonc
{
  // Ensure the login shell loads the profile
  "terminal.integrated.defaultProfile.linux": "bash",
  "terminal.integrated.defaultProfile.osx": "zsh",
  "terminal.integrated.shellIntegration.enabled": true
}
```

## Troubleshooting

### Profile not loading

1. **Check the profile shim exists:**

   ```powershell
   Test-Path $PROFILE.CurrentUserCurrentHost
   Get-Content $PROFILE.CurrentUserCurrentHost
   ```

   It should contain a loader that sources
   `~/.config/powershell/profile.ps1`.

2. **Verify PowerShell is not started with `-NoProfile`:**

   Open VS Code settings and check
   `terminal.integrated.profiles.windows`. Remove any `-NoProfile`
   argument from the PowerShell profile args.

3. **Re-run the profile linker:**

   ```powershell
   chezmoi apply
   ```

   This re-creates all profile shims including the VS Code one.

4. **Check the host name:**

   In the VS Code terminal, run:

   ```powershell
   $Host.Name
   ```

   It should be `ConsoleHost` (not `Visual Studio Code Host`, which
   is the PowerShell Extension's terminal).

### Starship prompt not appearing

- Ensure `starship` is on `PATH` — run `Get-Command starship`
- The profile has a PSReadLine readiness check; if PSReadLine fails
  to initialize, transient prompt is disabled but Starship still loads

### fzf keybindings not working

This is by design. In VS Code, `Ctrl+r` and `Ctrl+t` are reserved
for VS Code's own functionality. Use fzf commands directly:

```powershell
Invoke-FuzzyHistory      # Alternative to Ctrl+r
Invoke-FuzzySetLocation   # Alternative to Ctrl+t
```
