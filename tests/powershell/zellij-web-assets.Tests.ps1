# Tests for the cross-platform Zellij Web assets.
# Exercises: shared config knobs, Unix wrapper, Linux systemd unit,
# macOS LaunchAgent, and Unix registration script structure.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:ChezmoiConfigTemplate = Join-Path $repoRoot '.chezmoi.toml.tmpl'
  $script:ZellijTemplate = Join-Path $repoRoot 'home\.chezmoitemplates\zellij.kdl'
  $script:IgnoreTemplate = Join-Path $repoRoot 'home\.chezmoiignore.tmpl'
  $script:UnixWrapper = Join-Path $repoRoot 'home\dot_local\bin\executable_ensure-zellij-web'
  $script:SystemdUnit = Join-Path $repoRoot 'home\dot_config\systemd\user\zellij-web.service.tmpl'
  $script:LaunchAgent = Join-Path $repoRoot 'home\Library\LaunchAgents\com.kurone-kito.zellij-web.plist.tmpl'
  $script:WindowsRegisterScript = Join-Path $repoRoot 'home\run_onchange_after_80-register-zellij-web.ps1.tmpl'
  $script:WindowsEnsureWrapperTemplate = Join-Path $repoRoot 'home\dot_local\bin\executable_ensure-zellij-web.ps1.tmpl'
  $script:UnixRegisterScript = Join-Path $repoRoot 'home\run_onchange_after_80-register-zellij-web.sh.tmpl'
}

Describe 'zellij web assets' {

  It 'configures zellij web bind, port, sharing, and localhost https toggle' {
    $lines = Get-Content $script:ZellijTemplate

    $lines | Should -Contain 'web_server_ip {{ $zellijWebBind | quote }}'
    $lines | Should -Contain 'web_server_port {{ $zellijWebPort }}'
    $lines | Should -Contain 'web_sharing {{ $zellijWebSharing | quote }}'
    $lines | Should -Contain 'enforce_https_on_localhost {{ if $zellijWebEnforceHttpsLocalhost }}true{{ else }}false{{ end }}'
  }

  It 'uses non-trimming template syntax for variable assignments near web_client' {
    $lines = Get-Content $script:ZellijTemplate
    $assignmentLines = $lines | Where-Object { $_ -match '^\{\{ \$zellij.*:= dig' }

    $assignmentLines.Count | Should -BeGreaterThan 0
    foreach ($line in $assignmentLines) {
      $line | Should -Not -Match '^\{\{-'
    }
  }

  It 'exposes simplified_ui as a configurable template option' {
    $content = Get-Content $script:ZellijTemplate -Raw

    $content | Should -Match '\{\{ \$zellijSimplifiedUi := dig "zellij" "simplified_ui" false \. -\}\}'
    $content | Should -Match 'simplified_ui \{\{ if \$zellijSimplifiedUi \}\}true\{\{ else \}\}false\{\{ end \}\}'
  }

  It 'exposes web_client font and cursor settings as configurable template options' {
    $lines = Get-Content $script:ZellijTemplate

    $lines | Should -Contain '  font {{ $zellijWebClientFont | quote }}'
    $lines | Should -Contain '  cursor_blink {{ if $zellijWebClientCursorBlink }}true{{ else }}false{{ end }}'
    $lines | Should -Contain '  cursor_style {{ $zellijWebClientCursorStyle | quote }}'
    $lines | Should -Contain '  cursor_inactive_style {{ $zellijWebClientCursorInactiveStyle | quote }}'
  }

  It 'documents simplified_ui and web_client settings in the chezmoi config template' {
    $lines = Get-Content $script:ChezmoiConfigTemplate

    $lines | Should -Contain '#   simplified_ui = false             # true replaces Nerd Font glyphs with ASCII'
    $lines | Should -Contain '#   client_font = "''HackGen Console NF'', ''Hack Nerd Font'', monospace"'
    $lines | Should -Contain '#   client_cursor_blink = true'
    $lines | Should -Contain '#   client_cursor_style = "bar"      # "block", "bar", or "underline"'
  }

  It 'keeps certificate and key comment blocks on their own template lines' {
    $content = Get-Content $script:ZellijTemplate -Raw

    $content | Should -Match '\{\{ if \$zellijWebCert \}\}\r?\nweb_server_cert \{\{ \$zellijWebCert \| quote \}\}\r?\n\{\{ else \}\}\r?\n// web_server_cert "/path/to/cert\.pem"\r?\n\{\{ end \}\}\r?\n// A path to a key file'
    $content | Should -Match '\{\{ if \$zellijWebKey \}\}\r?\nweb_server_key \{\{ \$zellijWebKey \| quote \}\}\r?\n\{\{ else \}\}\r?\n// web_server_key "/path/to/key\.pem"\r?\n\{\{ end \}\}\r?\n/// Whether to enforce https connections to the web server'
  }

  It 'documents tailscale publication knobs in the chezmoi config template' {
    $lines = Get-Content $script:ChezmoiConfigTemplate

    $lines | Should -Contain '#   [data.zellij.web.tailscale]'
    $lines | Should -Contain '#   enabled = true                   # optional; publish through tailscale serve'
    $lines | Should -Contain '#   https_port = 443                 # optional tailnet HTTPS port'
  }

  It 'ignores platform-specific zellij artifacts on unsupported platforms' {
    $lines = Get-Content $script:IgnoreTemplate

    $lines | Should -Contain '80-register-zellij-web.sh'
    $lines | Should -Contain '.config/systemd/**'
    $lines | Should -Contain 'Library/LaunchAgents/**'
  }

  It 'provides a Unix ensure wrapper with foreground support' {
    $lines = Get-Content $script:UnixWrapper

    $lines | Should -Contain '  --foreground)'
    $lines | Should -Contain '    start_zellij_web "$(get_zellij_command)" "$@"'
    $lines | Should -Contain '    "$zellij_command" web --start --daemonize >/dev/null 2>&1'
    $lines | Should -Contain '  if [ "$DOTFILES_ZELLIJ_WEB_TAILSCALE_ENABLED" != "true" ]; then'
    $lines | Should -Contain '    "$tailscale_command" serve --bg --yes --https "$DOTFILES_ZELLIJ_WEB_TAILSCALE_HTTPS_PORT" "$serve_target" >/dev/null'
  }

  It 'defines a Linux systemd user service for zellij web' {
    $lines = Get-Content $script:SystemdUnit

    $lines | Should -Contain 'Type=oneshot'
    $lines | Should -Contain 'RemainAfterExit=yes'
    $lines | Should -Contain "ExecStart=/bin/sh -lc 'exec ""%h/.local/bin/ensure-zellij-web""'"
    $lines | Should -Not -Contain 'ExecStart=%h/.local/bin/ensure-zellij-web'
    $lines | Should -Contain 'WantedBy=default.target'
  }

  It 'defines a macOS LaunchAgent for zellij web' {
    $lines = Get-Content $script:LaunchAgent

    $lines | Should -Contain '    <string>com.kurone-kito.zellij-web</string>'
    $lines | Should -Contain '      <string>exec "$HOME/.local/bin/ensure-zellij-web"</string>'
    $lines | Should -Contain '    <key>RunAtLoad</key>'
    $lines | Should -Contain '    <true/>'
  }

  It 'hashes the Windows wrapper from the chezmoi source template path' {
    $content = Get-Content $script:WindowsRegisterScript -Raw

    $content | Should -Match 'include "dot_local/bin/executable_ensure-zellij-web\.ps1\.tmpl" \| sha256sum'
    $content | Should -Not -Match 'include "dot_local/bin/ensure-zellij-web\.ps1\.tmpl" \| sha256sum'
    Test-Path -LiteralPath $script:WindowsEnsureWrapperTemplate -PathType Leaf | Should -BeTrue
  }

  It 'uses systemctl on Linux and launchctl on macOS in the Unix registration script' {
    $lines = Get-Content $script:UnixRegisterScript

    $lines | Should -Contain '      systemctl --user enable zellij-web.service >/dev/null'
    $lines | Should -Contain '      systemctl --user restart zellij-web.service'
    $lines | Should -Contain '      launchctl bootstrap "$domain" "$plist"'
    $lines | Should -Contain '      launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true'
  }
}
