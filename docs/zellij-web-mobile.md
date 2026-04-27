# Zellij Web Client — Mobile Usage Guide

The Zellij web client allows browser-based access to terminal sessions.
This guide covers known limitations and recommended workarounds when
accessing the web client from mobile devices (e.g. iPhone, Android).

## Setup

Enable the web server and Tailscale publication in your
`chezmoi.toml`:

```toml
[data.zellij.web]
server = true

[data.zellij.web.tailscale]
enabled = true
```

After running `chezmoi apply`, start the web server:

```powershell
pwsh ~/.local/bin/ensure-zellij-web.ps1   # Windows
~/.local/bin/ensure-zellij-web             # Linux/macOS
```

Access via `https://<tailscale-hostname>/` from any device on your
tailnet.

## Nerd Font Glyphs

### Problem

Nerd Font icons (used by Starship prompts and Zellij plugins) appear
as broken squares or question marks on mobile browsers. This happens
because:

1. iOS Safari does **not** use fonts installed via configuration
   profiles for web content — only `@font-face` web fonts work.
2. Zellij's built-in web server does **not** serve custom web fonts.
3. Android browsers similarly lack Nerd Fonts by default.

### Mitigation: `simplified_ui`

Enable `simplified_ui` to replace Nerd Font glyphs in Zellij's own
UI (tab bar, status bar) with ASCII characters:

```toml
[data.zellij]
simplified_ui = true
```

This does **not** affect shell prompts (e.g. Starship). For prompt
icons, consider using a simpler Starship preset or accepting the
limitation on mobile.

### Mitigation: Font Fallback Chain

The `web_client.font` setting defaults to a Nerd Font fallback chain:

```
'HackGen Console NF', 'Hack Nerd Font', monospace
```

On devices where a Nerd Font **is** installed (desktop browsers), this
ensures correct rendering. On mobile, it falls back to `monospace`.

Override in `chezmoi.toml` if needed:

```toml
[data.zellij.web]
client_font = "'FiraCode Nerd Font', 'JetBrains Mono', monospace"
```

### Upstream Status

Zellij does not yet support serving custom web fonts via `@font-face`.
This would fully solve the mobile font issue. Track upstream progress
in the [Zellij issue tracker](https://github.com/zellij-org/zellij/issues).

## Font Size and Screen Width

### Problem

Mobile screens are narrow, making terminal sessions difficult to use.
Zellij's `web_client` block does not yet support a `font_size` option.

See: [Expose font size parameter (discussion #4482)](https://github.com/zellij-org/zellij/discussions/4482)

### Workarounds

1. **Landscape orientation** — roughly doubles the terminal width.

2. **Browser pinch-to-zoom** — adjust font size interactively. This
   is not persistent across page reloads.

3. **`zellij attach` via terminal app (recommended)** — instead of the
   browser, use a terminal app to get a native terminal experience with
   full font size control:

   ```sh
   # From Blink Shell, Termux, a-Shell, or any SSH client with Zellij:
   zellij attach https://<tailscale-hostname>/<session> --token <token>

   # Save credentials for 4 weeks:
   zellij attach https://<tailscale-hostname>/<session> --token <token> --remember
   ```

   This method connects directly to the remote Zellij web server
   without a browser. The terminal app controls font rendering,
   so Nerd Fonts work if installed on the device, and font size
   is fully configurable in the app settings.

4. **Desktop browser zoom** — use Ctrl+/Ctrl- to adjust font size
   (persistent per-site in most browsers).

## Cursor Settings

The web client supports cursor customization:

```toml
[data.zellij.web]
client_cursor_blink = true           # default: true
client_cursor_style = "bar"          # "block", "bar", or "underline"
client_cursor_inactive_style = "outline"  # "outline", "block", "bar", "underline"
```

## Related Documentation

- [Zellij Web Client](https://zellij.dev/documentation/web-client.html)
- [Zellij Options](https://zellij.dev/documentation/options.html)
- [Tailscale Serve](https://tailscale.com/kb/1312/serve)
