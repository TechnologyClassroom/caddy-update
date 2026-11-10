#!/bin/bash

# caddy-update.sh
# caddy-update.sh rebuilds caddy with coraza using xcaddy only if an update is
# available.
# Version v0.2.0

# Copyright (C) 2026 Michael McMahon
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script makes several assumptions.
# - The operating system is Debian-based such as Ubuntu.
# - bash, curl, jq are present.
# - An appropriate version of Go is installed and available in a $PATH
#   directory.
# - At least for initial development, this script is targeting only a few
#   dependencies.
#   - coraza-caddy which adds ModSecurity compatibility.
#     https://github.com/corazawaf/coraza-caddy
#   - logging.encoders which adds the option of saving combined log format.
#     https://github.com/caddyserver/transform-encoder
#   - caddy-akin which adds Akin-compatible request header fingerprinting.
#     https://rud.is/git/caddy-akin
# - xcaddy is installed and available in a $PATH directory.
#     go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
# - xcaddy builds are installed to /usr/bin/caddy.custom
#     sudo apt update
#     sudo apt install -y caddy
#     sudo dpkg-divert --divert /usr/bin/caddy.default --rename /usr/bin/caddy
#     sudo mv ./caddy /usr/bin/caddy.custom
#     sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.default 10
#     sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.custom 50
#     sudo systemctl restart caddy

set -euo pipefail
#set -euxo pipefail # DEBUG

# Parse arguments.
VERBOSE=false
DRY_RUN=false
while getopts ":vd" opt; do
  case $opt in
    v) VERBOSE=true;;
    d) DRY_RUN=true;;
    *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
  esac
done

# Constants
#UPSTREAM_URL_GO="https://go.dev/VERSION?m=text"
UPSTREAM_URL_XCADDY="https://api.github.com/repos/caddyserver/xcaddy/releases/latest"
UPSTREAM_URL_CADDY="https://api.github.com/repos/caddyserver/caddy/releases/latest"
UPSTREAM_URL_CORAZA="https://api.github.com/repos/corazawaf/coraza-caddy/releases/latest"
UPSTREAM_URL_CORAZA_CORERULES="https://api.github.com/repos/corazawaf/coraza-coreruleset/releases/latest"
#UPSTREAM_URL_LOG_ENCODER="https://api.github.com/repos/caddyserver/transform-encoder/releases/latest"
UPSTREAM_URL_LOG_ENCODER="https://api.github.com/repos/caddyserver/transform-encoder/commits/master"
# Not sure how to quickly fetch latest tag from cgit yet. rud.is/caddy-akin
# Probably need to keep a local repository and then check that so we help keep
# their site up. The version is in this file, but I cannot sneakily scrape it
# for obvious reasons. https://rud.is/git/caddy-akin/plain/version.go

# Dynamic variables
updates_needed=false
#ver_go_local="unknown"
#ver_go_upstr="unknown"
ver_xcaddy_local="unknown"
ver_xcaddy_upstr="unknown"
ver_caddy_local="unknown"
ver_caddy_upstr="unknown"
ver_coraza_local="unknown"
ver_coraza_upstr="unknown"
ver_coreruleset_local="unknown"
ver_coreruleset_upstr="unknown"
ver_log_encoder_local="unknown"
ver_log_encoder_upstr="unknown"

TEMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

# TMP DEBUG
# Ensure the locally installed Go tools (xcaddy) are available
#export PATH="$HOME/go/bin:$PATH"

# Functions

# Check if dependencies are present.
check_dependencies() {
  echo "Checking for dependencies..."

  # Validate if dependencies curl, jq, bash, sudo, and coreutils are present.
  for cmd in curl jq bash sudo awk cut echo grep caddy; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: $cmd is not installed."
      exit 1
      # TODO This does to check if a compatible version of the software is
      #   present.
      # TODO Ask if a dependency should attempt to be installed or attempt to
      #   install.
    fi
  done

  # Validate if dependency go exists in a $PATH directory.
  if ! command -v go >/dev/null 2>&1; then
    echo "Error: go is not installed or not in PATH."
    exit 1
    # TODO Ask if a go should attempt to be installed.
  fi

  # Validate if dependency xcaddy exists in a $PATH directory.
  if ! command -v xcaddy >/dev/null 2>&1; then
    echo "Error: xcaddy is not installed or not in PATH."
    exit 1
    # TODO Ask if a xcaddy should attempt to be installed.
  fi

  echo -e "\nAll dependencies are available."
}

# Normalize versions into an array. Echoes space-separated version parts padded
# to 8 elements.
normalize_version() {
  local v="$1"
  local num="${v#v}"
  IFS='.' read -ra parts <<< "$num"
  local result=()
  for ((i=0; i<8; i++)); do
    result+=("${parts[i]:-0}")
  done
  echo "${result[*]}"
}

# Compare semantic versions. Echoes 0 if equal, 1 if local > upstream, and -1
# if local < upstream.
compare_semver() {
  local ver_local="$1"
  local ver_upstr="$2"

  local ver_local_norm
  local ver_upstr_norm
  ver_local_norm="$(normalize_version "$ver_local")"
  ver_upstr_norm="$(normalize_version "$ver_upstr")"

  for ((i=0; i<8; i++)); do
    local local_part="${ver_local_norm[i]:-0}"
    local upstr_part="${ver_upstr_norm[i]:-0}"

    # Strip any non-numeric suffixes (like -rc1, -beta).
    local_part="${local_part%%-*}"
    upstr_part="${upstr_part%%-*}"

    if (( 10#$local_part > 10#$upstr_part )); then
      echo 1
      return
    elif (( 10#$local_part < 10#$upstr_part )); then
      echo -1
      return
    fi
  done
  echo 0
}

# Check for updates.
check_update() {
  local name="$1"
  local local_ver="$2"
  local upstr_ver="$3"

  if $VERBOSE; then
    echo "  [$name] Local: ${local_ver:-unknown},"
    echo "    Upstream: ${upstr_ver:-unknown}"
  fi

  if [[ "$local_ver" == "unknown" || -z "$local_ver" ]]; then
    echo "  $name: Local version unknown, assuming an update is needed."
    updates_needed=true
    return
  fi

  if [[ "$local_ver" == "$upstr_ver" ]]; then
    echo "  $name: Versions match ($local_ver). No update is needed."
    return
  fi

  local cmp
  cmp=$(compare_semver "$local_ver" "$upstr_ver")
  if [[ $cmp -eq -1 ]]; then
    echo "  [$name] Update available (Local: $local_ver,"
    echo "    Upstream: $upstr_ver)"
    updates_needed=true
  elif [[ $cmp -eq 1 ]]; then
    echo "  [$name] Local version is newer than upstream"
    echo "    (Local: $local_ver, Upstream: $upstr_ver)"
  else
    echo "  [$name] Versions match. No update needed."
  fi
}

# Check for dependencies.
check_dependencies

# TODO Check if Go has a new version available.
# TODO Ask if a go version should be fetched.
# ver_go_local=$(go version \
#   | awk '{ print $3 }')
# ver_go_upstr=$(curl -fsSL "$UPSTREAM_URL_XCADDY" \
#   | grep go \
#   | head -n 1)

# Check if xcaddy has a new version available.
if [[ "$updates_needed" != "true" ]]; then
  echo "Checking xcaddy..."
  ver_xcaddy_local=$(xcaddy -v 2>/dev/null \
    | awk '{ print $1 }' \
    || echo "unknown")
  ver_xcaddy_upstr=$(curl -s "$UPSTREAM_URL_XCADDY" \
    | jq -r ".tag_name")
  check_update "xcaddy" "$ver_xcaddy_local" "$ver_xcaddy_upstr"
  if [[ "$updates_needed" == "true" ]]; then
    echo -e "\nxcaddy update detected. Attempting to update xcaddy..."

    if $DRY_RUN; then
      echo "Dry run: Updates detected! caddy-update.sh would attempt to update"
      echo "xcaddy, but skipping for now..."
      exit 0
    fi

    # Attempt to update xcaddy.
    if ! go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    then
      echo "xcaddy compilation failed."
      exit 1
    fi
  fi
fi

# Check if caddy has a new version available.
if [[ "$updates_needed" != "true" ]]; then
  echo "Checking Caddy..."
  ver_caddy_local=$(caddy version 2>/dev/null \
    | awk '{ print $1 }' \
    || echo "unknown")
  ver_caddy_upstr=$(curl -s "$UPSTREAM_URL_CADDY" \
    | jq -r ".tag_name")
  check_update "Caddy" "$ver_caddy_local" "$ver_caddy_upstr"
fi

# Check if coraza-caddy has a new version available.
if [[ "$updates_needed" != "true" ]]; then
  echo "Checking Coraza-caddy..."
  ver_coraza_local=$(caddy list-modules --versions 2>/dev/null \
    | grep -i waf \
    | head -1 \
    | awk '{ print $2 }' \
    || echo "unknown")
  ver_coraza_upstr=$(curl -s "$UPSTREAM_URL_CORAZA" \
    | jq -r ".tag_name")
  check_update "Coraza-caddy" "$ver_coraza_local" "$ver_coraza_upstr"
fi

# Check if coraza-coreruleset has a new version available.
if [[ "$updates_needed" != "true" ]]; then
  echo "Checking Coraza-coreruleset..."
  ver_coreruleset_local=$(caddy build-info 2>/dev/null \
    | grep -i coreruleset \
    | head -1 \
    | awk '{ print $3 }' \
    || echo "unknown")
  ver_coreruleset_upstr=$(curl -s "$UPSTREAM_URL_CORAZA_CORERULES" \
    | jq -r ".tag_name")
  check_update "Coraza-coreruleset" "$ver_coreruleset_local" \
    "$ver_coreruleset_upstr"
fi

# Check if logging.encoders has a new version available.
if [[ "$updates_needed" != "true" ]]; then
  echo "Checking logging.encoders..."
  # Commented out this section as there are no releases for logging.encoders at
  # the time of this writing.
  #ver_log_encoder_local=$(caddy list-modules --versions 2>/dev/null \
  #  | grep 'caddy.logging.encoders.formatted' \
  #  | head -1 \
  #  | awk '{ print $2 }' \
  #  || echo "unknown")
  #ver_log_encoder_upstr=$(curl -s "$UPSTREAM_URL_LOG_ENCODER" \
  #  | jq -r ".tag_name")
  # logging.encoders does not have releases so we compare pseudo-version
  # instead. Pseudo-version looks like ba4124974830 instead of v4.25.0 like the
  # rest.
  ver_log_encoder_local=$(caddy list-modules --versions 2>/dev/null \
    | grep 'caddy.logging.encoders.formatted' \
    | awk '{ print $2 }' \
    | cut -d '-' -f 3 \
    || echo "unknown")
  ver_log_encoder_upstr=$(curl -s -H "Accept: application/vnd.github.VERSION.sha" \
    "$UPSTREAM_URL_LOG_ENCODER" \
    | grep -o "^............")
  check_update "logging.encoders" "$ver_log_encoder_local" "$ver_log_encoder_upstr"
fi

# Build only if updates are needed.
if [[ "$updates_needed" == "true" ]]; then
  echo -e "\nUpdates detected. Compiling Caddy with xcaddy..."

  if $DRY_RUN; then
    echo "Dry run: updates detected, would compile but skipping..."
    exit 0
  fi

  # Attempt to build caddy with xcaddy.
  if ! xcaddy build \
    --with github.com/corazawaf/coraza-caddy/v2 \
    --with go.rud.is/caddy-akin \
    --with github.com/caddyserver/transform-encoder
  then
    echo "Caddy compilation failed."
    exit 1
  fi

  # TODO Make init system configurable.
  # TODO Add a switch to only compile and not install.

  echo "Stopping caddy service..."
  sudo systemctl stop caddy

  # Backup the previously installed version so that the previous version can be
  # rolled back if necessary.
  echo "Backing up previous version..."
  sudo cp /usr/bin/caddy.custom /usr/bin/caddy.custom"$(date +%Y%m%d%H%M%S)"

  echo "Installing new compiled version of caddy..."
  sudo cp ./caddy /usr/bin/caddy.custom

  echo "Starting caddy service..."
  sudo systemctl start caddy

  echo "Testing caddy service..."
  systemctl is-active --quiet caddy && echo "Caddy service is running."

  # TODO Build test suite.
  # TODO Run test suite. If tests fail, rollback to previously working version.

  # TODO Add configuration file.
  # TODO Delete old versions except for a predefined number of the most
  # recent versions.

  echo -e "\ncaddy-update.sh was successful!"
  echo -e "\nSummary:"
  echo "xcaddy: $ver_xcaddy_local -> $ver_xcaddy_upstr"
  echo "Caddy: $ver_caddy_local -> $ver_caddy_upstr"
  echo "Coraza-caddy: $ver_coraza_local -> $ver_coraza_upstr"
  echo "Coraza-coreruleset: $ver_coreruleset_local -> $ver_coreruleset_upstr"
  echo "logging.encoders: $ver_log_encoder_local -> $ver_log_encoder_upstr"
else
  echo -e "\nAll caddy components appear to be up-to-date already."
  echo "Rebuilding is not necessary."
fi

exit 0
