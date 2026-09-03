#!/bin/bash

# caddy-update.sh
# caddy-update.sh rebuilds caddy with coraza using xcaddy only if an update is
# available.

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
# - An appropriate version of Go is present.
# - At least for initial development, this script is targeting only two
#   dependencies.
#   - [coraza-caddy](https://github.com/corazawaf/coraza-caddy) which adds
#     ModSecurity compatibility.
#   - [logging.encoders](https://github.com/caddyserver/transform-encoder)
#     which adds the option of saving combined log format.
# - xcaddy is installed at ./go/bin/xcaddy
#     go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
# - xcaddy builds are installed to /usr/bin/caddy.custom
#     sudo apt update
#     sudo apt install -y caddy
#     sudo dpkg-divert --divert /usr/bin/caddy.default --rename /usr/bin/caddy
#     sudo mv ./caddy /usr/bin/caddy.custom
#     sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.default 10
#     sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.custom 50
#     sudo systemctl restart caddy

# TODO Add safe bash.

# TODO Check if dependencies are present.
# If dependencies are missing, configure them.

# TODO Validate whether upstream versions look like versions.

# TODO Check installed versions compared to upstream versions.
# If no updates areavailable, exit.
# There are two basic ways that could be used:
# - Do the two strings match? If not, assume there is an update. This is the
#   easiest way.
# - Is the local version a lower value than the upstream version? If so,
#   attempt to update. This is mildly more difficult as the various version
#   formats need to be assessed.

# TODO Write function to compare versions.

echo "Checking for xcaddy updates..."
# Check upstream.
curl -s "https://api.github.com/repos/caddyserver/xcaddy/releases/latest" | jq -r ".tag_name"
# Check local.
./go/bin/xcaddy -v | awk '{ print $1 }'
# If local is less than upstream, update.
#go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

echo "Checking for caddy updates..."
# Check upstream.
curl -s "https://api.github.com/repos/caddyserver/caddy/releases/latest" | jq -r ".tag_name"
# Check local.
caddy -v | awk '{ print $1 }'
# If local is less than upstream, update.

echo "Checking for coraza updates..."
# Check upstream.
curl -s "https://api.github.com/repos/corazawaf/coraza-caddy/releases/latest" | jq -r ".tag_name"
# Check local.
caddy list-modules --versions | grep waf | awk '{ print $2 }'
# If local is less than upstream, update.

echo "Checking for coraza-coreruleset updates..."
# Check upstream.
curl -s "https://api.github.com/repos/corazawaf/coraza-coreruleset/releases/latest" | jq -r ".tag_name"
# Check local.
caddy build-info | grep coreruleset | awk '{ print $3 }'
# If local is less than upstream, update.

echo "Checking for logging.encoders updates..."
# This repo does not have releases so pseudo-version must be checked.
# Compare latest commit.
# curl -s "https://api.github.com/caddyserver/transform-encoder/releases/latest" | jq -r ".tag_name" # null
# https://github.com/caddyserver/transform-encoder/issues/72
# https://go.dev/ref/mod#pseudo-versions
# v0.0.0-20260423033309-ba4124974830
# "vX.0.0 if there is no such tag."-"A timestamp (yyyymmddhhmmss), which is the
# UTC time the revision was created."-"A revision identifier (abcdefabcdef),
# which is a 12-character prefix of the commit hash"
# Check upstream.
curl -s -H "Accept: application/vnd.github.VERSION.sha" "https://api.github.com/repos/caddyserver/transform-encoder/commits/master" | grep -o "^............"
# Check local.
caddy list-modules --versions | grep caddy.logging.encoders.formatted | awk '{ print $2 }' | cut -d '-' -f 3
# If local is less than upstream, update.

# TMP DEBUG
exit 0

# Compile caddy with addition modules using xcaddy.
echo "Compiling caddy..."
./go/bin/xcaddy build \
  --with github.com/corazawaf/coraza-caddy/v2 \
  --with github.com/caddyserver/transform-encoder

# TODO Check if xcaddy succeeded.

# TODO Test if server is working before deploying into production.
# TODO Test if Coraza is working before deploying into production.

echo "Stopping caddy service..."
sudo systemctl stop caddy

# Backup the previously installed version so that the previous version can be
# rolled back.
echo "Backing up previous version..."
sudo cp /usr/bin/caddy.custom /usr/bin/caddy.custom"$(date +%Y%m%d%H%M%S)"

echo "Installing new compiled version of caddy..."
sudo cp ./caddy /usr/bin/caddy.custom

echo "Starting caddy service..."
sudo systemctl start caddy

# TODO Test production.
# if tests fail, rollback.

# TODO Delete old versions except for a predefined number of the most
# recent versions.
