#!/usr/bin/env bats
# Tests for the Bash authorized_keys generator script.
# Exercises: managed-block creation, preservation of foreign
# out-of-band lines, block replacement, and idempotency.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SSH_DIR="$HOME/.ssh"
  AUTHORIZED="$SSH_DIR/authorized_keys"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/generate-authorized-keys.sh"

  mkdir -p "$SSH_DIR"
}

@test "creates authorized_keys with a managed block on first run" {
  echo "ssh-ed25519 AAAA primary@test" > "$SSH_DIR/primary.pub"
  echo "ssh-ed25519 BBBB secondary@test" > "$SSH_DIR/secondary.pub"

  run bash "$FIXTURE"
  assert_success

  run cat "$AUTHORIZED"
  assert_output --partial '# >>> chezmoi managed keys >>>'
  assert_output --partial 'ssh-ed25519 AAAA primary@test'
  assert_output --partial 'ssh-ed25519 BBBB secondary@test'
  assert_output --partial '# <<< chezmoi managed keys <<<'
}

@test "sets file permissions to 600" {
  echo "ssh-ed25519 AAAA primary@test" > "$SSH_DIR/primary.pub"

  run bash "$FIXTURE"
  assert_success

  run stat -c '%a' "$AUTHORIZED"
  assert_output '600'
}

@test "skips missing public keys" {
  echo "ssh-ed25519 BBBB secondary@test" > "$SSH_DIR/secondary.pub"

  run bash "$FIXTURE"
  assert_success
  assert_output --partial 'Skipped primary.pub (not found)'
  assert_output --partial 'Added secondary.pub'
}

@test "preserves a foreign line that predates the managed block" {
  echo "ssh-rsa FOREIGN from-cloud-provider" > "$AUTHORIZED"
  echo "ssh-ed25519 AAAA primary@test" > "$SSH_DIR/primary.pub"

  run bash "$FIXTURE"
  assert_success

  run cat "$AUTHORIZED"
  assert_output --partial 'ssh-rsa FOREIGN from-cloud-provider'
  assert_output --partial 'ssh-ed25519 AAAA primary@test'
}

@test "preserves foreign lines on both sides of an existing managed block" {
  echo "ssh-ed25519 AAAA primary@test" > "$SSH_DIR/primary.pub"
  run bash "$FIXTURE"
  assert_success

  {
    echo "ssh-rsa FOREIGN-BEFORE ssh-copy-id"
    cat "$AUTHORIZED"
    echo "ssh-rsa FOREIGN-AFTER manually-added"
  } > "$BATS_TEST_TMPDIR/new-authorized"
  mv "$BATS_TEST_TMPDIR/new-authorized" "$AUTHORIZED"

  echo "ssh-ed25519 BBBB secondary@test" > "$SSH_DIR/secondary.pub"
  run bash "$FIXTURE"
  assert_success

  run cat "$AUTHORIZED"
  assert_line --index 0 'ssh-rsa FOREIGN-BEFORE ssh-copy-id'
  assert_output --partial 'ssh-ed25519 AAAA primary@test'
  assert_output --partial 'ssh-ed25519 BBBB secondary@test'
  assert_line --index $((${#lines[@]} - 1)) 'ssh-rsa FOREIGN-AFTER manually-added'
}

@test "removes a key from the managed block when it disappears from config" {
  echo "ssh-ed25519 AAAA primary@test" > "$SSH_DIR/primary.pub"
  echo "ssh-ed25519 BBBB secondary@test" > "$SSH_DIR/secondary.pub"
  run bash "$FIXTURE"
  assert_success

  rm "$SSH_DIR/primary.pub"
  run bash "$FIXTURE"
  assert_success

  run cat "$AUTHORIZED"
  refute_output --partial 'ssh-ed25519 AAAA primary@test'
  assert_output --partial 'ssh-ed25519 BBBB secondary@test'
}

@test "re-running with unchanged keys produces no diff" {
  echo "ssh-ed25519 AAAA primary@test" > "$SSH_DIR/primary.pub"
  echo "ssh-ed25519 BBBB secondary@test" > "$SSH_DIR/secondary.pub"
  run bash "$FIXTURE"
  assert_success
  cp "$AUTHORIZED" "$BATS_TEST_TMPDIR/before"

  run bash "$FIXTURE"
  assert_success

  run diff "$BATS_TEST_TMPDIR/before" "$AUTHORIZED"
  assert_success
}

@test "creates an authorized_keys file with an empty managed block when no keys exist" {
  run bash "$FIXTURE"
  assert_success

  assert_file_exists "$AUTHORIZED"
  assert_output --partial 'WARNING: no public keys were found'
}

@test "falls back to append instead of dropping content when the end marker is missing" {
  printf 'ssh-rsa FOREIGN untouched\n# >>> chezmoi managed keys >>>\nssh-rsa STALE stale-key\n' > "$AUTHORIZED"
  echo "ssh-ed25519 AAAA primary@test" > "$SSH_DIR/primary.pub"

  run bash "$FIXTURE"
  assert_success

  run cat "$AUTHORIZED"
  assert_output --partial 'ssh-rsa FOREIGN untouched'
  assert_output --partial 'ssh-rsa STALE stale-key'
  assert_output --partial 'ssh-ed25519 AAAA primary@test'
}

@test "falls back to append instead of guessing when markers are duplicated" {
  printf '# >>> chezmoi managed keys >>>\nssh-rsa OLD1 old\n# <<< chezmoi managed keys <<<\nssh-rsa FOREIGN between-blocks\n# >>> chezmoi managed keys >>>\nssh-rsa OLD2 old\n# <<< chezmoi managed keys <<<\n' > "$AUTHORIZED"
  echo "ssh-ed25519 AAAA primary@test" > "$SSH_DIR/primary.pub"

  run bash "$FIXTURE"
  assert_success

  run cat "$AUTHORIZED"
  assert_output --partial 'ssh-rsa FOREIGN between-blocks'
  assert_output --partial 'ssh-ed25519 AAAA primary@test'
}
