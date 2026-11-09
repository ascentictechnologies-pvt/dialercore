# DialCore: installation and releases

DialCore is a multi-tenant contact-centre dialer (preview, progressive, predictive and broadcast dialing,
IVR designer, browser softphone, real-time monitoring and reports). This repository holds what you need
to install, upgrade or remove it. Release files are under
[Releases](https://github.com/ascentictechnologies-pvt/dialercore/releases).

## Install (one command)

On a fresh Ubuntu server (20.04, 22.04, 24.04 or 26.04; Debian 11 or 12; x86_64 or arm64), with the
domain's DNS A record already pointing at it:

```bash
curl -fsSL https://github.com/ascentictechnologies-pvt/dialercore/releases/latest/download/get-dialcore.sh | sudo bash
```

It asks for the domain name, an e-mail and the business time zone, then sets up PostgreSQL, .NET 10,
Asterisk, Kamailio, nginx with TLS, the firewall and DialCore. About 30–45 minutes.

## Other actions

```bash
curl -fsSL https://github.com/ascentictechnologies-pvt/dialercore/releases/latest/download/get-dialcore.sh | sudo bash -s -- upgrade
```

Replace `upgrade` with `resume`, `rollback`, `uninstall`, `check`, `summary` or `menu`. An upgrade keeps
the server's settings.

## Server without internet

Each release carries an offline bundle per Ubuntu release:
`dialcore-installer-<version>-offline-ubuntu24.04.tar.gz` and `...-ubuntu26.04.tar.gz`. Copy the one that
matches the server, check it against its `.sha256`, unpack it and run `sudo ./dialcore-install.sh`.

## Files

| File | What it is |
|---|---|
| [INSTALL.md](INSTALL.md) | Step-by-step installation, upgrade and uninstall guide |
| [get-dialcore.sh](get-dialcore.sh) | The one-command installer (downloads the latest release) |
| [dialcore-uninstall.sh](dialcore-uninstall.sh) | Standalone uninstaller |
| [docs/DialCore-Installer-Support-Guide.pdf](docs/DialCore-Installer-Support-Guide.pdf) | Guide for support staff |
| [docs/DialCore-User-Manual.pdf](docs/DialCore-User-Manual.pdf) | User manual (Platform Admin, Tenant Admin, Supervisor, Agent) |

Each [release](https://github.com/ascentictechnologies-pvt/dialercore/releases) also has the installer
bundle `dialcore-installer-<version>.tar.gz` with its `.sha256`.
