# Installing DialCore on an Ubuntu server: step by step

The bundle `dialcore-installer-<version>.tar.gz` holds everything: the installer, the DialCore API and
web app packages, the guide and checksums. One run sets up PostgreSQL, .NET 10, Asterisk 20, Kamailio,
nginx with TLS, the firewall and DialCore itself. It takes about 30–45 minutes, mostly building Asterisk.

## The menu and the support guide

Started with no command, `sudo ./dialcore-install.sh` shows a menu: Install, Resume, Upgrade, Rollback,
Uninstall, Check, Summary, Repair DB. Every action works with the offline bundle and with the normal one.
Step-by-step instructions for support staff: `docs/DialCore-Installer-Support-Guide.pdf` in the bundle.

Online, the one-command script runs the other actions too (it downloads the latest bundle first):
`curl -fsSL .../get-dialcore.sh | sudo bash -s -- upgrade` (or `resume`, `rollback`, `uninstall`, `check`, `summary`, `menu`).

## Quick install: one command

Point the domain's DNS A record at the server first, then on the server:

```bash
curl -fsSL https://github.com/ascentictechnologies-pvt/dialercore/releases/latest/download/get-dialcore.sh | sudo bash
```

It asks only for the domain name, an e-mail and the business time zone (Enter keeps the server's). Everything else is detected or generated. It then:

1. Checks the server runs a supported release (Ubuntu 20.04, 22.04, 24.04 or 26.04, or Debian 11 or 12, on x86_64 or arm64) before downloading anything, and stops otherwise.
2. Checks the domain points at this server (so the certificate can be issued).
3. Downloads the latest release, verifies its checksums and unpacks it in `/opt/dialcore-installer`.
4. Runs every installation step without further questions.

No domain (a test or LAN server)? Give the server's IP address instead of a domain name. The
installer then uses a self-signed certificate (browsers warn until it is accepted), skips the DNS
check and uses that IP for phones and browsers.

To skip even those questions:
`... | sudo bash -s -- --domain dialcore.example.com --email ops@example.com --timezone Asia/Kolkata`.
If it stops, fix what the message says and run the same command again: it resumes where it stopped.
Options: `--version 1.9.57`, `--public-ip <ip>`, `--cert selfsigned` (test server), `--verbose` (show every command and its output), `--interactive`
(offers the advanced settings), `--answers <file>`. Then continue with [6. First sign-in](#6-first-sign-in).

## Offline install: a server without internet (Ubuntu 24.04 or 26.04)

The offline bundle `dialcore-installer-<version>-offline-ubuntu<release>.tar.gz` (about 450 MB) carries
every package, the Asterisk source and DialCore itself, so the server needs no internet access at all.
There is one per Ubuntu release, **24.04** and **26.04** (x86_64 only): take the one matching
`grep VERSION_ID /etc/os-release` on the server. The installer refuses a bundle for another release. The installer sees the `offline/` folder and uses only it:
the server's own package sources are left untouched.

1. **Copy** the bundle and its checksum to the server (USB disk, or `scp` from a computer on the same network):
   ```bash
   scp dialcore-installer-<version>-offline-ubuntu<release>.tar.gz* <user>@<server>:~
   ```
2. **Check and unpack** on the server:
   ```bash
   sha256sum -c dialcore-installer-<version>-offline-ubuntu<release>.tar.gz.sha256   # must print: OK
   tar -xzf dialcore-installer-<version>-offline-ubuntu<release>.tar.gz
   cd dialcore-installer-<version>
   ```
3. **Look first** (changes nothing): `sudo ./dialcore-install.sh check`. Free any busy port it lists.
4. **Install**: `sudo ./dialcore-install.sh install` (add `--verbose` to watch every command).
   - Domain: the name users will open, or the server's IP address if there is no DNS.
   - E-mail, then the time zone (Enter keeps the server's).
   - "Change advanced settings?": Enter (No).
   - Check the summary and answer `y`. It takes about 30–45 minutes, mostly building Asterisk.
   - The certificate is self-signed (no Let's Encrypt without internet): browsers warn until it is
     accepted, or give your own certificate under the advanced settings (`existing`).
5. **Note the result**: the last screen prints every address, port, user and password
   (`sudo ./dialcore-install.sh summary` shows it again). Keep an offline copy of `KEK` from
   `/var/lib/dialcore-installer/answers.env`.
6. Continue with [6. First sign-in](#6-first-sign-in). The licence file is copied to a computer that
   can open the web app, then uploaded there as usual.

If a step fails, fix the cause and run `sudo ./dialcore-install.sh install --resume`.
To start again from the first step: `sudo ./dialcore-uninstall.sh`, then `sudo ./dialcore-install.sh install`.
To remove it, see [10. Uninstalling](#10-uninstalling): it works offline too.

The sections below describe the online installation done by hand.

## 1. Before you start

| Need | Detail |
|---|---|
| Server | Ubuntu 20.04, 22.04, 24.04 or 26.04 (or Debian 11/12), x86_64 or arm64; 4 GB RAM and 20 GB free disk or more; ideally a fresh server |
| Access | An account that can use `sudo`, and SSH to the server |
| Domain | A DNS **A record** for the DialCore name (for example `dialcore.example.com`) pointing at the server's public IP |
| Internet | The server must reach `apt` mirrors, `downloads.asterisk.org`, `deb.kamailio.org`, `dot.net` and Let's Encrypt |
| Ports | 80 and 443 (web, certificate), 5060 (Asterisk SIP), 5090 (Kamailio SIP), 10000–20000/UDP (call audio), and your SSH port. These ports are fixed. Open them on any cloud or office firewall in front of the server |
| Details to hand | Domain name, an e-mail for certificate notices, the server's own IP, its public IP (if behind NAT), the IPs of your SIP carriers / voice servers |

Passwords for the database roles, Asterisk ARI/AMI and the signing keys are **generated**. Everything is saved in `/var/lib/dialcore-installer/answers.env`
(readable by root only).

## 2. Copy the bundle to the server

From your computer:

```bash
scp dialcore-installer-<version>.tar.gz dialcore-installer-<version>.tar.gz.sha256 <user>@<server>:~
```

## 3. Unpack and check it

On the server:

```bash
sha256sum -c dialcore-installer-<version>.tar.gz.sha256      # must print: OK
tar -xzf dialcore-installer-<version>.tar.gz
cd dialcore-installer-<version>
sha256sum -c SHA256SUMS                                     # every file: OK
```

## 4. See what is already there (changes nothing)

```bash
sudo ./dialcore-install.sh check
```

It lists the operating system, memory, disk, internet access, each component (installed or missing)
and any busy ports. Free a busy port, or stop whatever uses it, before installing.

## 5. Run the installation

```bash
sudo ./dialcore-install.sh install
```

Add `--verbose` to watch every command and its output as it runs (it is always in
`/var/log/dialcore-installer.log`).

1. **Questions.** Only three: the domain name, an administrator e-mail and the business time zone
   (e.g. `Asia/Kolkata`; Enter keeps the server's). The server clock follows that zone; DialCore itself
   keeps UTC and shows each user times in their own zone. Then
   "Change advanced settings?": press Enter (No) and everything else is detected, generated or
   left at its standard value. Answer `y` only to change any of these (Enter keeps the value in
   `[brackets]`):
   - Components: install Asterisk and Kamailio on this server (yes for a single-server install).
   - Network: server IP, public IP (the same if not behind NAT), trusted carrier IPs, SSH port, ports.
   - Install directory (`/opt/Ascentic/Dialer`) and service account (`dialcore`).
   - Packages: the API and web app packages from `packages/` are offered; press Enter.
   - Certificate: `letsencrypt-http` (port 80 must be reachable from the internet), `letsencrypt-dns`
     (you add a DNS TXT record when asked), `existing` (give your certificate and key files), or
     `selfsigned` (testing only).
   - Database, Asterisk and security settings: press Enter to generate passwords and keep defaults.
2. **Summary.** Check it and answer `y`.
3. **Steps.** They run one after another without further questions: preflight, questions, base
   packages, system tuning (open-file and process limits, kernel network settings, apport off), PostgreSQL, .NET, Asterisk, Kamailio, certificates, database, application, database roles, Asterisk configuration, Kamailio configuration,
   nginx, firewall, verify.
4. **Result.** The last step checks every service, the web address and the API's link to Asterisk, then
   prints every address, port, user name and password, including the exact values for the Create Server
   form. It is saved in `/var/lib/dialcore-installer/install-summary.txt` (root only); show it again with
   `sudo ./dialcore-install.sh summary`.

**Keep an offline copy of `KEK`** from `/var/lib/dialcore-installer/answers.env`. Data encrypted at rest
cannot be read without it.

## 6. First sign-in

1. Open `https://<your domain>`. The first visit shows the System config page: create the platform admin.
2. **Licence:** as platform admin open **License**, send the **Installation ID** shown there to Ascentic
   support, and upload the licence file you receive. Tenants and sign-ins are limited by it.
3. **Voice server:** under Telephony > Voice servers add this server with the IP, ARI port, ARI user and
   ARI password printed at the end of the installation.
4. Create a tenant, its administrator, trunks and campaigns as usual.

## 7. If something goes wrong

| Situation | What to do |
|---|---|
| A step fails | Read the message and `/var/log/dialcore-installer.log`, fix the cause, then `sudo ./dialcore-install.sh install --resume`. Finished steps are skipped |
| Where am I? | `sudo ./dialcore-install.sh status` |
| Undo everything | `sudo ./dialcore-install.sh rollback` (asks before deleting the database and backs it up first) |
| Undo part of it | `sudo ./dialcore-install.sh rollback --to <step>`, then `install --resume` |
| Kamailio tables missing, or `permission denied` for `asterisk_rt` / `kamailio_rw` in the PostgreSQL log | `sudo ./dialcore-install.sh db-repair` (creates the missing Kamailio tables, grants again, restarts the API and Kamailio; safe to repeat) |
| Try without changing anything | add `--dry-run` |
| API logs | `/opt/Ascentic/Dialer/BackEnd/logs/` and `journalctl -u dialcore-api -n 100` |
| No call audio | Public IP answer and the RTP port range (10000–20000/UDP) on every firewall in front of the server |

## 8. Unattended installation

```bash
cat > answers.env <<'EOF'
DOMAIN=dialcore.example.com
ADMIN_EMAIL=ops@example.com
SIP_IP=10.0.0.5
PUBLIC_IP=203.0.113.10
TRUSTED_IPS=10.0.0.5
CERT_MODE=letsencrypt-http
EOF
sudo ./dialcore-install.sh install --yes --answers answers.env
```

Any value not in the file takes its default; passwords are generated.

## 9. Upgrading later

Copy the new version's bundle to the server (the offline one for the server's Ubuntu release, or the normal
one), unpack it and run from its folder:

```bash
sudo ./dialcore-install.sh upgrade
```

1. The database is backed up to `/opt/Ascentic/Dialer/BackEnd/backups/` first; if that fails, nothing changes.
2. The new API is unpacked beside the running one and switched in; it updates the database schema when it
   starts. If it doesn't start, the previous API is put back automatically.
3. The new web app replaces the old one (kept as `/opt/Ascentic/Dialer/Frontend.previous`).
4. The database repair runs (missing Kamailio tables, database access for Asterisk and Kamailio).

**Not changed:** `dialcore.env` (keys, passwords, settings), nginx, Asterisk, Kamailio, certificates and the
saved answers. The end of the run prints how to go back to the previous version.

`install` is for a new server: on an installed one it skips the finished steps, so it doesn't replace the
API or web app.

## 10. Uninstalling

From the installer folder (the same one used to install, or a newer one):

```bash
sudo ./dialcore-uninstall.sh            # same as: sudo ./dialcore-install.sh uninstall
sudo ./dialcore-uninstall.sh --dry-run  # only show what would be removed
```

1. It shows what was installed and asks for confirmation.
2. It removes DialCore: the application, its service, web site, certificates, settings, firewall rules,
   kernel tuning and service accounts, and puts back every file it had changed.
3. It asks before deleting the database; answer `y` to delete it (a backup is saved first in
   `/var/backups/dialcore`), anything else keeps it.
4. Shared components are removed only when nothing else on the server needs them:

| Component | Removed only if |
|---|---|
| Asterisk | this installer built it and no other program is connected to it |
| PostgreSQL | no databases are left except PostgreSQL's own (kept if you kept the DialCore database) |
| nginx | no other web site is configured |
| .NET | no other service or running program uses it |
| fail2ban, ufw | no other jails or firewall rules are left |
| any other package | removing it would not remove any other installed software |
| curl, git, sudo, cron, wget, openssl, gnupg, tar | never (general tools) |

The last lines list what was removed and what was kept, with the reason. Details are in
`/var/log/dialcore-installer.log`. Only a server installed with this installer can be uninstalled this way.
