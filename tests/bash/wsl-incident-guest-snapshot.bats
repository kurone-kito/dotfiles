#!/usr/bin/env bats
# cspell:ignore pgscan kswapd pgsteal pswpin pgmajfault
# Fixture-only coverage for the optional read-only procfs guest snapshot.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  SNAPSHOT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_wsl-incident-guest-snapshot"
  PROC_ROOT="$BATS_TEST_TMPDIR/proc"
  mkdir -p "$PROC_ROOT/pressure"
  cat >"$PROC_ROOT/meminfo" <<'EOF'
MemTotal:       100000 kB
MemAvailable:   40000 kB
SwapTotal:       1000 kB
SwapFree:         700 kB
EOF
  cat >"$PROC_ROOT/pressure/memory" <<'EOF'
some avg10=0.10 avg60=0.20 avg300=0.30 total=900
full avg10=0.01 avg60=0.02 avg300=0.03 total=90
EOF
  cat >"$PROC_ROOT/vmstat" <<'EOF'
pgscan_kswapd 15
pgscan_direct 7
pgsteal_kswapd 11
pgsteal_direct 3
workingset_refault 40
pswpin 5
pswpout 8
pgfault 100
pgmajfault 2
EOF
}

@test "emits memory, PSI, swap, and bounded VM-counter rates from fixtures" {
  previous="$BATS_TEST_TMPDIR/previous.tsv"
  cat >"$previous" <<'EOF'
pgscan_kswapd	10
pgscan_direct	7
pgsteal_kswapd	10
pgsteal_direct	3
workingset_refault	30
pswpin	5
pswpout	6
pgfault	80
pgmajfault	1
EOF

  run "$SNAPSHOT" --proc-root "$PROC_ROOT" --previous "$previous" --interval-seconds 2

  assert_success
  assert_output --partial '"memory":{"status":"ok","unit":"kB","total":100000,"available":40000}'
  assert_output --partial '"swap":{"status":"ok","unit":"kB","total":1000,"used":300}'
  assert_output --partial '"avg10":0.10,"avg60":0.20,"avg300":0.30,"totalUsec":900'
  assert_output --partial '"pgscan_kswapd":{"status":"ok","value":5,"perSecond":2.500}'
  assert_output --partial '"pswpout":{"status":"ok","value":2,"perSecond":1.000}'
  [ "$(printf '%s' "$output" | wc -c)" -le 4096 ]
  refute_output --partial "$PROC_ROOT"
  refute_output --partial 'Secret-Distro'
}

@test "marks the first sample and counter resets unavailable" {
  run "$SNAPSHOT" --proc-root "$PROC_ROOT" --interval-seconds 60

  assert_success
  assert_output --partial '"pgscan_kswapd":{"status":"unavailable","value":null,"perSecond":null}'

  previous="$BATS_TEST_TMPDIR/previous.tsv"
  printf 'pgscan_kswapd\t999\n' >"$previous"
  run "$SNAPSHOT" --proc-root "$PROC_ROOT" --previous "$previous" --interval-seconds 1

  assert_success
  assert_output --partial '"pgscan_kswapd":{"status":"unavailable","value":null,"perSecond":null}'
}

@test "discards an oversized stdin baseline and continues without rates" {
  previous="$BATS_TEST_TMPDIR/oversized-previous.tsv"
  {
    printf 'pgscan_kswapd\t14\n'
    head -c 4097 /dev/zero | tr '\0' x
  } >"$previous"

  run bash -c 'exec 0<"$1"; shift; exec "$@"' _ "$previous" "$SNAPSHOT" \
    --proc-root "$PROC_ROOT" --interval-seconds 1 --previous-stdin

  assert_success
  assert_output --partial '"memory":{"status":"ok","unit":"kB","total":100000,"available":40000}'
  assert_output --partial '"pgscan_kswapd":{"status":"unavailable","value":null,"perSecond":null}'
  [ "$(printf '%s' "$output" | wc -c)" -le 4096 ]
}

@test "discards an oversized file baseline and continues without rates" {
  previous="$BATS_TEST_TMPDIR/oversized-previous-file.tsv"
  {
    printf 'pgscan_kswapd\t14\n'
    head -c 4097 /dev/zero | tr '\0' x
  } >"$previous"

  run "$SNAPSHOT" --proc-root "$PROC_ROOT" --interval-seconds 1 --previous "$previous"

  assert_success
  assert_output --partial '"pgscan_kswapd":{"status":"unavailable","value":null,"perSecond":null}'
}

@test "does not wait for an oversized stdin producer to close" {
  timeout_cmd=$(command -v timeout || command -v gtimeout || true)
  [[ -n $timeout_cmd ]] || skip "timeout or gtimeout is unavailable"

  previous="$BATS_TEST_TMPDIR/oversized-previous.pipe"
  mkfifo "$previous"
  exec 9<>"$previous"
  printf 'pgscan_kswapd\t14\n' >&9
  head -c 4097 /dev/zero | tr '\0' x >&9

  run "$timeout_cmd" 5 "$SNAPSHOT" --proc-root "$PROC_ROOT" --interval-seconds 1 --previous-stdin <"$previous"
  exec 9>&-

  assert_success
  assert_output --partial '"memory":{"status":"ok","unit":"kB","total":100000,"available":40000}'
  assert_output --partial '"pgscan_kswapd":{"status":"unavailable","value":null,"perSecond":null}'
}

@test "ignores a previous-counter FIFO without opening or waiting for it" {
  previous="$BATS_TEST_TMPDIR/previous.pipe"
  mkfifo "$previous"
  exec 9<>"$previous"

  run "$SNAPSHOT" --proc-root "$PROC_ROOT" --interval-seconds 1 --previous "$previous"
  exec 9>&-

  assert_success
  assert_output --partial '"pgscan_kswapd":{"status":"unavailable","value":null,"perSecond":null}'
}

@test "discards a short stdin baseline when its producer stays open" {
  timeout_cmd=$(command -v timeout || command -v gtimeout || true)
  [[ -n $timeout_cmd ]] || skip "timeout or gtimeout is unavailable"

  previous="$BATS_TEST_TMPDIR/previous-short.pipe"
  mkfifo "$previous"
  exec 9<>"$previous"
  printf 'pgscan_kswapd\t14\n' >&9

  run "$timeout_cmd" 2 "$SNAPSHOT" --proc-root "$PROC_ROOT" --interval-seconds 1 --previous-stdin <"$previous"
  exec 9>&-

  assert_success
  assert_output --partial '"pgscan_kswapd":{"status":"unavailable","value":null,"perSecond":null}'
}

@test "normalizes integer counters and rejects non-JSON PSI numeric forms" {
  cat >"$PROC_ROOT/meminfo" <<'EOF'
MemTotal: 010 kB
MemAvailable: 08 kB
SwapTotal: 000 kB
SwapFree: 000 kB
EOF
  cat >"$PROC_ROOT/pressure/memory" <<'EOF'
some avg10=00.10 avg60=0.20 avg300=0.30 total=0900
full avg10=0.01 avg60=0.02 avg300=0.03 total=90
EOF

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '"memory":{"status":"ok","unit":"kB","total":10,"available":8}'
  assert_output --partial '"psi":{"status":"ok","some":null'
  refute_output --partial '00.10'
  refute_output --partial '"total":0900'
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$output" | jq -e . >/dev/null
  fi
}

@test "formats rates with a dot decimal regardless of awk caller locale" {
  previous="$BATS_TEST_TMPDIR/previous.tsv"
  awk_log="$BATS_TEST_TMPDIR/awk-locales.log"
  fake_bin="$BATS_TEST_TMPDIR/fake-awk-bin"
  real_awk=$(command -v awk)
  mkdir -p "$fake_bin"
  cat >"$previous" <<'EOF'
pgscan_kswapd	14
pgscan_direct	6
pgsteal_kswapd	10
pgsteal_direct	2
workingset_refault	39
pswpin	4
pswpout	7
pgfault	99
pgmajfault	1
EOF
  cat >"$fake_bin/awk" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${LC_ALL:-unset}" >>"$AWK_RATE_LOCALE_LOG"
exec "$REAL_AWK" "$@"
EOF
  chmod +x "$fake_bin/awk"

  run env REAL_AWK="$real_awk" AWK_RATE_LOCALE_LOG="$awk_log" PATH="$fake_bin:$PATH" \
    "$SNAPSHOT" --proc-root "$PROC_ROOT" --previous "$previous" --interval-seconds 2

  assert_success
  assert_output --partial '"pgscan_kswapd":{"status":"ok","value":1,"perSecond":0.500}'
  [ "$(tail -n 1 "$awk_log")" = C ]
}

@test "reports unavailable capabilities without leaking proc paths" {
  rm "$PROC_ROOT/pressure/memory"
  cat >"$PROC_ROOT/meminfo" <<'EOF'
MemTotal: 1000 kB
MemAvailable: 500 kB
EOF
  rm "$PROC_ROOT/vmstat"

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '"status":"partial"'
  assert_output --partial '"swap":{"status":"unavailable"'
  assert_output --partial '"psi":{"status":"unavailable","some":null,"full":null}'
  assert_output --partial '"pswpin":{"status":"unavailable","value":null,"perSecond":null}'
  refute_output --partial "$PROC_ROOT"
}

@test "marks otherwise complete memory data partial when PSI is unavailable" {
  rm "$PROC_ROOT/pressure/memory"

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '"schemaVersion":1,"status":"partial"'
  assert_output --partial '"psi":{"status":"unavailable","some":null,"full":null}'
}

@test "marks otherwise complete memory data partial when VM counters are unavailable" {
  rm "$PROC_ROOT/vmstat"

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '"schemaVersion":1,"status":"partial"'
  assert_output --partial '"pgscan_kswapd":{"status":"unavailable","value":null,"perSecond":null}'
}

@test "rejects oversized procfs files before parsing their contents" {
  printf 'MemTotal: 1000 kB\nMemAvailable: 500 kB\nSwapTotal: 10 kB\nSwapFree: 5 kB\n' >"$PROC_ROOT/meminfo"
  head -c 65537 /dev/zero | tr '\0' x >>"$PROC_ROOT/meminfo"

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output '{"schemaVersion":1,"status":"unavailable","error":"memory-data-unavailable"}'
}

@test "reports missing procfs as a stable unavailable record" {
  run "$SNAPSHOT" --proc-root "$BATS_TEST_TMPDIR/no-such-proc"

  assert_success
  assert_output '{"schemaVersion":1,"status":"unavailable","error":"procfs-unavailable"}'
}

@test "reports the missing awk dependency without reading procfs" {
  fake_bin="$BATS_TEST_TMPDIR/no-awk-bin"
  mkdir -p "$fake_bin"
  ln -s "$(command -v bash)" "$fake_bin/bash"

  run env PATH="$fake_bin" "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output '{"schemaVersion":1,"status":"unavailable","error":"required-command-missing"}'
}

_render_ignore() {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  printf '%s\n' '{ "data": {} }' > "$config"
  chezmoi execute-template --file "$BATS_TEST_DIRNAME/../../home/.chezmoiignore.tmpl" \
    --config "$config" --config-format json \
    --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" \
    --source "$BATS_TEST_DIRNAME/../../home" \
    --destination "$BATS_TEST_TMPDIR/destination"
}

@test "renders only the collector for the matching operating system" {
  run --separate-stderr _render_ignore linux
  assert_success
  assert_output --partial '.local/bin/wsl-incident-capture.ps1'
  refute_output --partial '.local/bin/wsl-incident-guest-snapshot'

  run --separate-stderr _render_ignore windows
  assert_success
  assert_output --partial '.local/bin/wsl-incident-guest-snapshot'
  refute_output --partial '.local/bin/wsl-incident-capture.ps1'

  run --separate-stderr _render_ignore darwin
  assert_success
  assert_output --partial '.local/bin/wsl-incident-guest-snapshot'
  assert_output --partial '.local/bin/wsl-incident-capture.ps1'
}
