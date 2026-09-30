[![Docker Image CI](https://github.com/carfanatic93/guacamole-fish/actions/workflows/docker-image.yml/badge.svg)](https://github.com/carfanatic93/guacamole-fish/actions/workflows/docker-image.yml)

# Docker Guacamole

> Fork of [flcontainers/guacamole](https://github.com/flcontainers/guacamole) with additional fixes, most notably a patched guacd terminal emulator that silently ignores unsupported OSC escape sequences (e.g. OSC 7 current directory, OSC 8 hyperlinks, OSC 133 shell integration), DCS queries, and CSI sequences with a private prefix it does not support (e.g. the kitty keyboard query `CSI ? u`). Without it, modern shells such as fish 4.x (Debian 13) produce garbage like `ile://host/path` in front of the prompt and draw the prompt over the login banner. Patches applied to guacamole-server live in `patches/guacamole-server/`.

A Docker Container for [Apache Guacamole](https://guacamole.apache.org/), a client-less remote desktop gateway. It supports standard protocols like VNC, RDP, and SSH over HTML5.

Supported Linux OS: amd64 (arm64 builds are disabled in this fork; re-add `linux/arm64` to `platforms` in the workflows if needed)

This container runs the guacamole web client, the guacd server and a postgres database (version 16).

The image builds guacd from guacamole-server source during docker build and enables a broad optional dependency set (RDP, VNC, SSH, Telnet, Kubernetes, PulseAudio, WebP, and FFmpeg/libav tooling support) so useful codecs/plugins are available out of the box.

FreeRDP is also compiled from source (currently 3.24.2) with audio/video codec support explicitly enabled: FFmpeg-based DSP and H.264, OpenH264, Opus, GSM, FAAC/FAAD2 AAC, SOX resampler, JPEG, and PulseAudio. This avoids relying on whichever codec flags the Alpine distro package maintainer chose to include.

FreeRDP is also built from source with FFmpeg, swscale, OpenH264, Opus, GSM, AAC, soxr, and PulseAudio support enabled, rather than relying on Alpine's packaged feature set. Guacamole 1.6.0 currently treats FreeRDP 3.x as experimental, so broad codec/media support comes with that upstream caveat.

On first start with an existing PostgreSQL 13 data directory in `/config/postgres`, the container automatically performs an in-place major upgrade to PostgreSQL 16 using `pg_upgrade`. The original PG13 data directory is preserved as `/config/postgres-v13` until you remove it after verifying the upgrade.

## Usage (Multi-Arch)

```shell
docker run \
  -p 8080:8080 \
  -v </path/to/config>:/config \
  ghcr.io/carfanatic93/guacamole-fish
```

## Parameters

The parameters are split into two halves, separated by a colon, the left hand side representing the host and the right the container side.

* `-p 8080:8080` - Binds the service to port 8080 on the Docker host, **required**
* `-v /config` - The config and database location, **required**
* `-v /etc/locatime` - Recommended to sync container time with host (Docker)
* `-e TZ` - Set Timezone (standard format: Europe/Berlin)
* `-e EXTENSIONS` - See below for details.

## Enabling Extensions

Extensions can be enabled using the `-e EXTENSIONS` variable. Multiple extensions can be enabled using a comma separated list without spaces.

For example:

```shell
docker run \
  -p 8080:8080 \
  -v </path/to/config>:/config \
  -v /etc/localtime:/etc/localtime:ro \
  -e TZ="UTC" \
  -e EXTENSIONS="auth-ldap,auth-duo" \
  ghcr.io/carfanatic93/guacamole-fish
```

**Extension List:**
- auth-duo
- auth-header
- auth-jdbc-mysql
- auth-jdbc-postgresql
- auth-jdbc-sqlserver
- auth-json
- auth-ldap
- auth-quickconnect
- auth-sso-openid
- auth-sso-saml
- auth-sso-cas
- auth-totp
- auth-ban
- display-statistics
- vault-ksm
- history-recording-storage

More information: [Guacamole release notes](https://guacamole.apache.org/releases/)

You should only enable the extensions you require, if an extensions is not configured correctly in the `guacamole.properties` file it may prevent the system from loading. See the [official documentation](https://guacamole.apache.org/doc/gug/) for more details.

## Default User

The default username is `guacadmin` with password `guacadmin`.

## Windows-based Docker Hosts

Mapped volumes behave differently when running Docker for Windows and you may encounter some issues with PostgreSQL file system permissions. To avoid these issues, and still retain your config between container upgrades and recreation, you can use the local volume driver, as shown in the `docker-compose.yml` example below. When using this setup be careful to gracefully stop the container or data may be lost.

```yml
version: "3"
services:
  guacamole:
    image: ghcr.io/carfanatic93/guacamole-fish
    container_name: guacamole
    environment:
      TZ: 'UTC'
      EXTENSIONS: 'auth-totp,auth-ldap'
    volumes:
      - postgres:/config
      - /etc/localtime:/etc/localtime:ro
    ports:
      - 8080:8080
volumes:
  postgres:
    driver: local
```

## License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the [GNU General Public License](./LICENSE) for more details.

