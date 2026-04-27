#!/bin/sh
# Neovim environment — skip DSR terminal background detection.
# Neovim 0.11+ queries the terminal for background color on startup;
# WSL, SSH, and multiplexer sessions often timeout, causing a delay.
# Since options.lua already sets background = "dark", auto-detection
# is unnecessary.

export NVIM_NO_BG_WAIT=1
