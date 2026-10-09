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

# Write /proc/vmstat with the eight counters outside the refault family,
# followed by the given refault lines.
_write_vmstat() {
  {
    printf '%s\n' 'pgscan_kswapd 15' 'pgscan_direct 7' 'pgsteal_kswapd 11' \
      'pgsteal_direct 3' 'pswpin 5' 'pswpout 8' 'pgfault 100' 'pgmajfault 2'
    (($# == 0)) || printf '%s\n' "$@"
  } >"$PROC_ROOT/vmstat"
}

@test "reports ok for a legacy refault line and leaves the split counters unavailable" {
  previous="$BATS_TEST_TMPDIR/previous.tsv"
  printf 'workingset_refault\t30\n' >"$previous"

  run "$SNAPSHOT" --proc-root "$PROC_ROOT" --previous "$previous" --interval-seconds 2

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"ok",'
  assert_output --partial '"workingset_refault":40,"workingset_refault_anon":null,"workingset_refault_file":null,'
  assert_output --partial '"workingset_refault":{"status":"ok","value":10,"perSecond":5.000}'
  assert_output --partial '"workingset_refault_anon":{"status":"unavailable","value":null,"perSecond":null}'
  assert_output --partial '"workingset_refault_file":{"status":"unavailable","value":null,"perSecond":null}'
}

@test "reads split refault counters and reports ok without the legacy line" {
  _write_vmstat 'workingset_refault_anon 3' 'workingset_refault_file 37171155'
  previous="$BATS_TEST_TMPDIR/previous.tsv"
  printf 'workingset_refault_anon\t1\nworkingset_refault_file\t37171055\n' >"$previous"

  run "$SNAPSHOT" --proc-root "$PROC_ROOT" --previous "$previous" --interval-seconds 2

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"ok",'
  assert_output --partial '"workingset_refault":null,"workingset_refault_anon":3,"workingset_refault_file":37171155,'
  assert_output --partial '"workingset_refault":{"status":"unavailable","value":null,"perSecond":null}'
  assert_output --partial '"workingset_refault_anon":{"status":"ok","value":2,"perSecond":1.000}'
  assert_output --partial '"workingset_refault_file":{"status":"ok","value":100,"perSecond":50.000}'
}

@test "reports all three refault counters when both layouts are present" {
  _write_vmstat 'workingset_refault 40' 'workingset_refault_anon 3' 'workingset_refault_file 9'

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"ok",'
  assert_output --partial '"workingset_refault":40,"workingset_refault_anon":3,"workingset_refault_file":9,'
}

@test "marks the sample partial when neither refault layout is present" {
  _write_vmstat

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"partial",'
  assert_output --partial '"pgscan_kswapd":15,'
  assert_output --partial '"workingset_refault":null,"workingset_refault_anon":null,"workingset_refault_file":null,'
}

@test "marks the sample partial when only the anon split counter is present" {
  _write_vmstat 'workingset_refault_anon 3'

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"partial",'
  assert_output --partial '"workingset_refault":null,"workingset_refault_anon":3,"workingset_refault_file":null,'
}

@test "marks the sample partial when only the file split counter is present" {
  _write_vmstat 'workingset_refault_file 9'

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"partial",'
  assert_output --partial '"workingset_refault":null,"workingset_refault_anon":null,"workingset_refault_file":9,'
}

@test "keeps the legacy line sufficient when only one split counter accompanies it" {
  _write_vmstat 'workingset_refault 40' 'workingset_refault_file 9'

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"ok",'
  assert_output --partial '"workingset_refault":40,"workingset_refault_anon":null,"workingset_refault_file":9,'
}

@test "counts a zero split counter as present" {
  _write_vmstat 'workingset_refault_anon 0' 'workingset_refault_file 5'

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"ok",'
  assert_output --partial '"workingset_refault":null,"workingset_refault_anon":0,"workingset_refault_file":5,'
}

@test "treats a non-numeric split counter as missing" {
  _write_vmstat 'workingset_refault_anon abc' 'workingset_refault_file 7'

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"partial",'
  assert_output --partial '"workingset_refault":null,"workingset_refault_anon":null,"workingset_refault_file":7,'
}

@test "reads the first of duplicated split counter lines" {
  _write_vmstat 'workingset_refault_anon 1' 'workingset_refault_file 7' 'workingset_refault_file 9'

  run "$SNAPSHOT" --proc-root "$PROC_ROOT"

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"ok",'
  assert_output --partial '"workingset_refault_anon":1,"workingset_refault_file":7,'
}

@test "keeps schemaVersion 1 and the existing counter and delta fields unchanged" {
  previous="$BATS_TEST_TMPDIR/previous.tsv"
  cat >"$previous" <<'EOT'
pgscan_kswapd	14
pgscan_direct	6
pgsteal_kswapd	10
pgsteal_direct	2
workingset_refault	39
pswpin	4
pswpout	7
pgfault	99
pgmajfault	1
EOT

  run "$SNAPSHOT" --proc-root "$PROC_ROOT" --previous "$previous" --interval-seconds 1

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"ok",'
  assert_output --partial '"counters":{"pgscan_kswapd":15,"pgscan_direct":7,"pgsteal_kswapd":11,"pgsteal_direct":3,"workingset_refault":40,"workingset_refault_anon":null,"workingset_refault_file":null,"pswpin":5,"pswpout":8,"pgfault":100,"pgmajfault":2}'
  for key in pgscan_kswapd pgscan_direct pgsteal_kswapd pgsteal_direct workingset_refault pswpin pswpout pgfault pgmajfault; do
    assert_output --partial "\"$key\":{\"status\":\"ok\",\"value\":1,\"perSecond\":1.000}"
  done
}

@test "keeps a full eleven-counter baseline within 4 KiB and reads its last key" {
  keys=(pgscan_kswapd pgscan_direct pgsteal_kswapd pgsteal_direct workingset_refault workingset_refault_anon workingset_refault_file pswpin pswpout pgfault pgmajfault)
  previous="$BATS_TEST_TMPDIR/full-previous.tsv"
  : >"$previous"
  : >"$PROC_ROOT/vmstat"
  for key in "${keys[@]}"; do
    printf '%s\t%s\n' "$key" 1000000000000000000 >>"$previous"
    printf '%s %s\n' "$key" 1000000000000000100 >>"$PROC_ROOT/vmstat"
  done
  [ "$(wc -c <"$previous")" -le 4096 ]

  run bash -c 'exec 0<"$1"; shift; exec "$@"' _ "$previous" "$SNAPSHOT" \
    --proc-root "$PROC_ROOT" --interval-seconds 2 --previous-stdin

  assert_success
  assert_output --partial '{"schemaVersion":1,"status":"ok",'
  for key in "${keys[@]}"; do
    assert_output --partial "\"$key\":{\"status\":\"ok\",\"value\":100,\"perSecond\":50.000}"
  done
  [ "$(printf '%s' "$output" | wc -c)" -le 4096 ]
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
