# Tests for the cross-platform Zellij Web assets.
# Exercises: shared config knobs, Unix wrapper, Linux systemd unit,
# macOS LaunchAgent, and Unix registration script structure.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:ZellijTemplate = Join-Path $repoRoot 'home\.chezmoitemplates\zellij.kdl'
  $script:IgnoreTemplate = Join-Path $repoRoot 'home\.chezmoiignore.tmpl'
  $script:UnixWrapper = Join-Path $repoRoot 'home\dot_local\bin\executable_ensure-zellij-web'
  $script:SystemdUnit = Join-Path $repoRoot 'home\dot_config\systemd\user\zellij-web.service.tmpl'
  $script:LaunchAgent = Join-Path $repoRoot 'home\Library\LaunchAgents\com.kurone-kito.zellij-web.plist.tmpl'
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
    $lines | Should -Contain '  "$zellij_command" web --start --daemonize >/dev/null 2>&1'
  }

  It 'defines a Linux systemd user service for zellij web' {
    $lines = Get-Content $script:SystemdUnit

    $lines | Should -Contain 'Type=oneshot'
    $lines | Should -Contain 'RemainAfterExit=yes'
    $lines | Should -Contain 'ExecStart=%h/.local/bin/ensure-zellij-web'
    $lines | Should -Contain 'WantedBy=default.target'
  }

  It 'defines a macOS LaunchAgent for zellij web' {
    $lines = Get-Content $script:LaunchAgent

    $lines | Should -Contain '    <string>com.kurone-kito.zellij-web</string>'
    $lines | Should -Contain '      <string>exec "$HOME/.local/bin/ensure-zellij-web"</string>'
    $lines | Should -Contain '    <key>RunAtLoad</key>'
    $lines | Should -Contain '    <true/>'
  }

  It 'uses systemctl on Linux and launchctl on macOS in the Unix registration script' {
    $lines = Get-Content $script:UnixRegisterScript

    $lines | Should -Contain '      systemctl --user enable zellij-web.service >/dev/null'
    $lines | Should -Contain '      systemctl --user restart zellij-web.service'
    $lines | Should -Contain '      launchctl bootstrap "$domain" "$plist"'
    $lines | Should -Contain '      launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true'
  }
}
