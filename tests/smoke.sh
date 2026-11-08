#!/usr/bin/env bash
#
# Tests the images loaded by `docker buildx bake --load` for a single platform.
# `make test` builds and tests every platform.
#
# Usage: tests/smoke.sh <platform>

set -euo pipefail

platform=${1:?usage: tests/smoke.sh <platform>}
repo_root=$(cd "$(dirname "$0")/.." && pwd)

ubuntu_tools="container-images-test/ubuntu-tools:test"
spire_tools="container-images-test/spire-tools:test"
spire_server="container-images-test/spire-server:test"

# elf_machine is the e_machine field of an ELF header for this platform.
case "$platform" in
  linux/amd64) elf_machine=62 aws_arch=x86_64 ;;
  linux/arm64) elf_machine=183 aws_arch=aarch64 ;;
  *) echo "Unsupported platform: $platform" >&2; exit 1 ;;
esac

failures=0

pass() {
  echo "ok   - $1"
}

fail() {
  echo "FAIL - $1"
  failures=$((failures + 1))
}

# Prints the version a Dockerfile pins, so that a version bump updates the test.
pinned() {
  sed -n "s/^ARG $2=//p" "$repo_root/$1"
}

# expect_output <image> <expected> <command> [args...]
#
# Passes if the command succeeds and its output contains the expected text.
expect_output() {
  local image=$1 expected=$2 output
  shift 2
  if output=$(docker run --rm --platform "$platform" --entrypoint "$1" "$image" "${@:2}" 2>&1) \
    && grep -qF -- "$expected" <<<"$output"; then
    pass "$image: $* contains '$expected'"
  else
    fail "$image: $* should contain '$expected', got: $output"
  fi
}

# expect_arch <image> <path>
#
# Reads the binary's ELF header rather than running it. A binary for the wrong
# architecture still runs when QEMU is set up, which hides the problem.
expect_arch() {
  local image=$1 path=$2 container binary machine
  binary=$(mktemp)
  container=$(docker create --platform "$platform" "$image")
  if docker cp --quiet --follow-link "$container:$path" "$binary"; then
    # e_machine is 2 bytes at offset 18. Both supported architectures are
    # little-endian, as are the hosts this runs on.
    machine=$(od -An -tu2 -j18 -N2 "$binary" | tr -d ' ')
    if [ "$machine" = "$elf_machine" ]; then
      pass "$image: $path is built for $platform"
    else
      fail "$image: $path should have ELF machine $elf_machine, got: ${machine:-none}"
    fi
  else
    fail "$image: could not copy $path"
  fi
  docker rm "$container" >/dev/null
  rm -f "$binary"
}

test_ubuntu_tools() {
  expect_arch "$ubuntu_tools" /usr/bin/jq
  expect_output "$ubuntu_tools" "OpenSSL" openssl version
  expect_output "$ubuntu_tools" "VIM" vim --version
  expect_output "$ubuntu_tools" "UnZip" unzip -v
  expect_output "$ubuntu_tools" "GNU Wget" wget --version
  expect_output "$ubuntu_tools" "curl" curl --version
  expect_output "$ubuntu_tools" "jq-" jq --version
}

test_spire_tools() {
  local binary
  for binary in spire-server spire-agent spiffe-helper spiffe-aws-assume-role \
    cosign aws_signing_helper certigo; do
    expect_arch "$spire_tools" "/usr/bin/$binary"
  done
  expect_arch "$spire_tools" /usr/local/bin/aws

  expect_output "$spire_tools" "$(pinned Dockerfile.spire-tools SPIRE_VERSION)" spire-server --version
  expect_output "$spire_tools" "$(pinned Dockerfile.spire-tools SPIRE_VERSION)" spire-agent --version
  expect_output "$spire_tools" "$(pinned Dockerfile.spire-tools SPIFFE_HELPER_VERSION)" spiffe-helper -version
  expect_output "$spire_tools" "$(pinned Dockerfile.spire-tools ROLESANYWHERE_VERSION)" aws_signing_helper version
  expect_output "$spire_tools" "$(pinned Dockerfile.spire-tools CERTIGO_VERSION)" certigo --version
  # spiffe-aws-assume-role has no version command and cosign isn't pinned.
  expect_output "$spire_tools" "Usage: spiffe-aws-assume-role" spiffe-aws-assume-role --help
  expect_output "$spire_tools" "GitVersion" cosign version
  expect_output "$spire_tools" "exe/$aws_arch" aws --version
  expect_output "$spire_tools" "psql (PostgreSQL)" psql --version

  expect_output "$spire_tools" "999" id -u postgres
  expect_output "$spire_tools" "venv works" bash -c \
    'python3 -m venv /tmp/venv && /tmp/venv/bin/python -c "print(\"venv works\")"'
  expect_output "$spire_tools" "smoke-test" bash -c \
    'openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/key.pem -out /tmp/cert.pem -subj /CN=smoke-test -days 1 && certigo dump /tmp/cert.pem'
}

test_spire_server() {
  expect_arch "$spire_server" /usr/bin/tpm_attestor_server
  expect_output "$spire_server" "$(pinned Dockerfile.spire-server SPIRE_VERSION)" /opt/spire/bin/spire-server --version
  test_spire_server_loads_tpm_plugin
}

# The server exits if it can't load and configure a plugin, so a healthy server
# means the TPM plugin works.
test_spire_server_loads_tpm_plugin() {
  local container healthy=false
  container=$(docker run --detach --platform "$platform" \
    --mount "type=bind,source=$repo_root/tests/spire-server.conf,target=/tmp/server.conf,readonly" \
    "$spire_server" -config /tmp/server.conf)
  for _ in $(seq 60); do
    if docker exec "$container" /opt/spire/bin/spire-server healthcheck >/dev/null 2>&1; then
      healthy=true
      break
    fi
    [ "$(docker inspect --format '{{.State.Running}}' "$container")" = "true" ] || break
    sleep 1
  done
  if [ "$healthy" = "true" ]; then
    pass "$spire_server: spire-server is healthy with the TPM plugin loaded"
  else
    fail "$spire_server: spire-server should be healthy with the TPM plugin loaded, logs:"
    docker logs "$container" 2>&1 | tail -n 20
  fi
  docker rm --force "$container" >/dev/null
}

test_ubuntu_tools
test_spire_tools
test_spire_server

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed on $platform"
  exit 1
fi
echo "All checks passed on $platform"
