# xcaddy-updater
A work-in-progress (WIP) Bash script to automate rebuilding Caddy web server
with plugins only when necessary.

## Dependencies

The script depends on this programs being present:

- bash
- sudo
- go
- xcaddy
- caddy
- jq
- curl
- awk
- cut
- echo
- grep

This script makes several assumptions which may differ from your environment.
These assumptions are listed here:

- The operating system is based on Debian such as Ubuntu or Trisquel.
- xcaddy is installed at ./go/bin/xcaddy relative to the script.
- xcaddy builds are installed to /usr/bin/caddy.custom
- At least for initial development, this script is targeting only two
  dependencies.
  - [coraza-caddy](https://github.com/corazawaf/coraza-caddy) which adds
    ModSecurity compatibility.
  - [logging.encoders](https://github.com/caddyserver/transform-encoder) which
    adds the option of saving combined log format.

xcaddy is installed with this method:

    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

Custom caddy builds are installed with [this method](https://caddyserver.com/docs/build#package-support-files-for-custom-builds-for-debianubunturaspbian):

    sudo apt update
    sudo apt install -y caddy
    sudo dpkg-divert --divert /usr/bin/caddy.default --rename /usr/bin/caddy
    sudo mv ./caddy /usr/bin/caddy.custom
    sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.default 10
    sudo update-alternatives --install /usr/bin/caddy caddy /usr/bin/caddy.custom 50
    sudo systemctl restart caddy

If you would like to work towards making this script more robust and account
for other variations of installation preferences, contributions are welcome
while demands are not.

## How to use
This is currently a WIP script so instructions may change.

Read the script before running as the script is easy to read and may make
assumptions that differ from your environment.

Currently, the script is simply run as a non-root user with sudo privileges
with this command:

    bash caddy-update.sh

If the assumptions match your environment, you should be running the latest
caddy version on the server after the script completes.

## Background
When the caddy package is installed through a package manager, caddy does not
include additional plugins. If you want to add plugins, you need to recompile
either manually or with xcaddy because plugins are included within the binary.

The xcaddy project does not include automation and the consensus seems to be
that sysadmins should be updating manually so that they know if there is a
regression. With the rise of automated vulnerability research, updates need to
be applied faster than when I remember or notice that an update is released for
caddy or one of the plugins.

Some automation exists with the docker method, but I have yet to see any
scripts that check if a rebuild needs to occur. I also do not want to add
abstraction by using docker across all of my servers. The consensus seems to be
that it is acceptable for everyone to continuously rebuild caddy even if it is
not needed. This is inefficiently wasteful for system and network resources.
Why is everyone continually rebuilding if they are already running the latest
build?

## License
Apache-2.0

This is to match xcaddy so that it can be upstreamed without asking.

## Contributing
This project is free software. You are welcome to contribute.
