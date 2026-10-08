#!/bin/sh
# cspell:words gsub
# Default Node.js address-selection budget for slow dual-stack connections.
#
# Node.js gives every non-final connection attempt its own address-selection
# budget (250ms by default), so a slow but usable address can be abandoned
# early. One operator reported ETIMEOUT from the Bitwarden CLI that chezmoi
# runs during `chezmoi apply` and found that the npm CLI on Node.js Jod
# LTS with a 2000ms budget improved it (#588; no single-variable
# comparison exists). The cause is unproven: 2000ms is that
# operator-confirmed mitigation, not an optimal universal value, not proof
# of a Bitwarden defect, and no repair for an unreachable IPv6 route.
# Node.js ignores the option when a connection selects an address family
# or a local address explicitly.
#
# This exports --network-family-autoselection-attempt-timeout=2000 through
# NODE_OPTIONS for every Node.js tool, so it applies to `bw` too. It does so
# only when all of these hold; otherwise the environment is left untouched
# and startup stays quiet:
#
# - a `node` that accepts the option is on PATH. A local probe checks that,
#   with mise auto-install and network access switched off so a mise shim
#   cannot install anything. There is no portable shell timeout for it.
# - NODE_OPTIONS parses the way Node.js parses it (only a space separates
#   options, a double quote toggles quoting, a backslash escapes inside
#   quotes) and does not already name the option. The exact option name is
#   matched, with `_` and `-` interchangeable, so a related option such as
#   --network-family-autoselection does not count. Any existing value, in
#   any spelling, wins byte for byte.
#
# The default is appended after the existing content. NODE_OPTIONS is only
# ever handed to awk through the environment and never evaluated. Source this
# file after 60-mise.sh so the probe sees the node that mise puts on PATH.
# The PowerShell counterpart is powershell/conf.d/35-node-options.ps1.

_dotfiles_node_options_apply() {
  command -v node >/dev/null 2>&1 || return 0

  if [ -n "${NODE_OPTIONS:-}" ]; then
    # The verdict is `absent`, `present` or `invalid`. A failing or missing
    # awk yields no verdict, and only `absent` may continue.
    _dotfiles_node_options_state=$(
      _DOTFILES_NODE_OPTIONS_VALUE=$NODE_OPTIONS awk '
        BEGIN {
          s = ENVIRON["_DOTFILES_NODE_OPTIONS_VALUE"]
          target = "network-family-autoselection-attempt-timeout"
          n = length(s)
          quoted = 0
          have = 0
          found = 0
          tok = ""
          for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (c == "\\" && quoted) {
              if (i == n) { print "invalid"; exit }
              i++
              c = substr(s, i, 1)
            } else if (c == " " && !quoted) {
              if (have && is_target(tok)) found = 1
              tok = ""
              have = 0
              continue
            } else if (c == "\"") {
              quoted = !quoted
              continue
            }
            tok = tok c
            have = 1
          }
          if (quoted) { print "invalid"; exit }
          if (have && is_target(tok)) found = 1
          print (found ? "present" : "absent")
        }
        function is_target(t,   name, eq) {
          if (substr(t, 1, 2) != "--") return 0
          name = substr(t, 3)
          eq = index(name, "=")
          if (eq > 0) name = substr(name, 1, eq - 1)
          gsub(/_/, "-", name)
          return name == target
        }
      ' </dev/null 2>/dev/null
    ) || _dotfiles_node_options_state=invalid
    [ "$_dotfiles_node_options_state" = absent ] || return 0
  fi

  # The non-empty script argument matters: Windows PowerShell 5.1 drops an
  # empty-string argument, and this probe stays the same in both shells.
  MISE_AUTO_INSTALL=0 MISE_EXEC_AUTO_INSTALL=0 MISE_OFFLINE=1 \
    NODE_OPTIONS=--network-family-autoselection-attempt-timeout=2000 \
    command node -e 0 </dev/null >/dev/null 2>&1 || return 0

  if [ -n "${NODE_OPTIONS:-}" ]; then
    NODE_OPTIONS="$NODE_OPTIONS --network-family-autoselection-attempt-timeout=2000"
  else
    NODE_OPTIONS=--network-family-autoselection-attempt-timeout=2000
  fi
  export NODE_OPTIONS
}

_dotfiles_node_options_apply
unset -f _dotfiles_node_options_apply
unset _dotfiles_node_options_state
