#!/usr/bin/env bash
# One-command DialCore server install for Ubuntu/Debian.
#
#   curl -fsSL https://github.com/ascentictechnologies-pvt/dialercore/releases/latest/download/get-dialcore.sh | sudo bash
#
# Downloads the installer bundle of the latest release (or --version), checks its checksums, unpacks it
# and runs the installer unattended. It asks only for the domain name and an e-mail (or takes them from
# --domain / --email); everything else is detected or generated. Before installing it checks that the
# domain's DNS points at this server, so the certificate step can't fail on that. Running it again
# resumes an interrupted install with the answers already given.
#
# Other actions (the latest bundle is downloaded, then the installer runs that action on this server):
#   curl -fsSL .../get-dialcore.sh | sudo bash -s -- upgrade     new API and web app, settings kept
#   ... | sudo bash -s -- resume | rollback | uninstall | check | summary | menu
#
# Options:
#   --domain <name>        DialCore web address, e.g. dialcore.example.com
#   --email <address>      e-mail for certificate expiry notices
#   --timezone <zone>      business time zone, e.g. Asia/Kolkata (default: the server's)
#   --version <x.y.z>      release to install (default: latest)
#   --public-ip <ip>       public IP if detection picks the wrong one
#   --cert <mode>          letsencrypt-http (default) | letsencrypt-dns | existing | selfsigned
#   --answers <file>       extra installer answers (VAR=value lines; see INSTALL.md)
#   --interactive          offer the installer's advanced settings (IPs, ports, folders, database)
#   --verbose              show every installer command and its output on screen
#   --skip-dns-check       install even if the domain does not point at this server yet
#   -h, --help             this help
set -Eeuo pipefail

REPO="${DIALCORE_REPO:-ascentictechnologies-pvt/dialercore}"
BASE_DIR=/opt/dialcore-installer
STATE_DIR=/var/lib/dialcore-installer
ACTION=install; DOMAIN=""; EMAIL=""; VERSION=""; PUBLIC_IP=""; CERT=""; EXTRA_ANSWERS=""; INTERACTIVE=0; SKIP_DNS=0; VERBOSE=0; TIMEZONE=""

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!  \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗  %s\033[0m\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -Eeuo/p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | grep '^#' | sed 's/^# \{0,1\}//' || true; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --timezone) TIMEZONE="$2"; shift 2 ;;
    --version) VERSION="${2#v}"; shift 2 ;;
    --public-ip) PUBLIC_IP="$2"; shift 2 ;;
    --cert) CERT="$2"; shift 2 ;;
    --answers) EXTRA_ANSWERS="$(realpath "$2")"; shift 2 ;;
    --interactive) INTERACTIVE=1; shift ;;
    --verbose|-v) VERBOSE=1; shift ;;
    --skip-dns-check) SKIP_DNS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    install|resume|upgrade|rollback|uninstall|check|summary|menu) ACTION="$1"; shift ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

# ---- checks ---------------------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "run as root: curl -fsSL ... | sudo bash"
# Only these fields: os-release also sets VERSION ("24.04.5 LTS (Noble Numbat)"), which would replace ours.
eval "$(grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release 2>/dev/null)" && [[ -n "${ID:-}" ]] \
  || die "cannot read /etc/os-release"
# Same rule as the installer (lib/common.sh supported_os_problem; each offline bundle is narrower, one
# release): checked before anything is downloaded, for the actions that install. Uninstall, check and
# summary work anywhere.
if [[ "$ACTION" == install || "$ACTION" == resume || "$ACTION" == upgrade ]]; then
  case "${ID:-unknown} ${VERSION_ID:-}" in
    "ubuntu 20.04"|"ubuntu 22.04"|"ubuntu 24.04"|"ubuntu 26.04"|"debian 11"|"debian 12") ;;
    *) die "this server runs ${ID:-unknown} ${VERSION_ID:-}; DialCore installs on Ubuntu 20.04, 22.04, 24.04 or 26.04, or Debian 11 or 12" ;;
  esac
  ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
  [[ "$ARCH" == amd64 || "$ARCH" == arm64 ]] || die "this server is $ARCH; DialCore installs on amd64 (x86_64) or arm64"
  say "server: ${PRETTY_NAME:-$ID $VERSION_ID} ($ARCH), supported"
fi
for t in curl tar sha256sum getent; do
  command -v "$t" >/dev/null || { say "installing $t"; apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl tar coreutils ca-certificates >/dev/null; break; }
done
if [[ -n "$EXTRA_ANSWERS" && ! -f "$EXTRA_ANSWERS" ]]; then die "answers file not found: $EXTRA_ANSWERS"; fi

# Prompts read the terminal: when piped into bash, stdin is the script itself.
ask() { # ask VAR "Question" validator-regex
  local var="$1" q="$2" re="$3" reply
  [[ -e /dev/tty ]] || die "$var is needed: pass it with --${var,,} (no terminal to ask on)"
  while true; do
    read -r -p "$q: " reply < /dev/tty || die "no answer for $var"
    [[ "$reply" =~ $re ]] && break
    warn "that doesn't look right, try again"
  done
  printf -v "$var" '%s' "$reply"
}
FQDN_RE='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'
EMAIL_RE='^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
IP_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

if [[ "$ACTION" == install ]]; then
# A resumed install keeps the answers saved by the first run.
saved() { [[ -f "$STATE_DIR/answers.env" ]] && sed -n "s/^$1=//p" "$STATE_DIR/answers.env" | tail -1 | tr -d "'\""; }
[[ -n "$DOMAIN" ]] || DOMAIN="$(saved DOMAIN || true)"
[[ -n "$EMAIL" ]] || EMAIL="$(saved ADMIN_EMAIL || true)"
[[ -n "$DOMAIN" ]] || ask DOMAIN "Domain name for DialCore (e.g. dialcore.example.com, or the server IP for a test/LAN install)" "$FQDN_RE"
[[ -n "$EMAIL" ]] || ask EMAIL "E-mail for certificate notices" "$EMAIL_RE"
[[ -n "$TIMEZONE" ]] || TIMEZONE="$(saved TIMEZONE || true)"
if [[ -z "$TIMEZONE" ]]; then
  TZ_DEFAULT="$(timedatectl show -p Timezone --value 2>/dev/null || echo Etc/UTC)"
  [[ -e /dev/tty ]] && read -r -p "Time zone of the business (e.g. Asia/Kolkata) [$TZ_DEFAULT]: " TIMEZONE < /dev/tty || true
  TIMEZONE="${TIMEZONE:-$TZ_DEFAULT}"
fi
[[ "$TIMEZONE" != *..* && -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "unknown time zone: $TIMEZONE (see: timedatectl list-timezones)"
[[ "$DOMAIN" =~ $FQDN_RE ]] || die "not a domain name: $DOMAIN"
[[ "$EMAIL" =~ $EMAIL_RE ]] || die "not an e-mail address: $EMAIL"
[[ -z "$CERT" || "$CERT" =~ ^(letsencrypt-http|letsencrypt-dns|existing|selfsigned)$ ]] || die "unknown --cert $CERT"

# An IP address instead of a domain (e.g. a LAN server): no free certificate exists for it, so a
# self-signed one; and that IP is the one phones and browsers reach.
if [[ "$DOMAIN" =~ $IP_RE ]]; then
  [[ -n "$CERT" ]] || CERT=selfsigned
  [[ -n "$PUBLIC_IP" ]] || PUBLIC_IP="$DOMAIN"
  [[ "$CERT" == selfsigned || "$CERT" == existing ]] || die "--cert $CERT needs a domain name, not an IP address"
  warn "installing on IP $DOMAIN with a self-signed certificate: browsers show a warning until it is accepted"
fi
# The free certificate is issued only if the domain already points at this server.
[[ -n "$PUBLIC_IP" ]] || PUBLIC_IP="$(curl -fsS -m 8 https://api.ipify.org 2>/dev/null || true)"
[[ "$PUBLIC_IP" =~ $IP_RE ]] || die "could not detect this server's public IP; pass --public-ip"
if [[ "${CERT:-letsencrypt-http}" == letsencrypt-http && $SKIP_DNS == 0 ]]; then
  dns_ips="$(getent ahostsv4 "$DOMAIN" | awk '{print $1}' | sort -u | xargs)"
  [[ " $dns_ips " == *" $PUBLIC_IP "* ]] || die "$DOMAIN points at '${dns_ips:-nothing}', not at this server ($PUBLIC_IP).
   Add a DNS A record $DOMAIN -> $PUBLIC_IP, wait a few minutes and run this again
   (or use --cert selfsigned for a test server, or --skip-dns-check if the IP is NATed differently)."
fi

fi

# ---- download ---------------------------------------------------------------------------------------
if [[ -z "$VERSION" ]]; then
  VERSION="$(curl -fsSL -m 20 "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)" \
    || true
  [[ -n "$VERSION" ]] || die "could not find the latest release of $REPO (is the repository public?); pass --version"
fi
NAME="dialcore-installer-$VERSION"
URL="https://github.com/$REPO/releases/download/v$VERSION"
mkdir -p "$BASE_DIR"; cd "$BASE_DIR"
if [[ ! -x "$NAME/dialcore-install.sh" ]]; then
  say "downloading DialCore $VERSION"
  curl -fL --progress-bar --retry 3 -o "$NAME.tar.gz" "$URL/$NAME.tar.gz" || die "download failed: $URL/$NAME.tar.gz"
  curl -fsSL --retry 3 -o "$NAME.tar.gz.sha256" "$URL/$NAME.tar.gz.sha256" || die "checksum download failed"
  sha256sum -c --quiet "$NAME.tar.gz.sha256" || die "the download is damaged (checksum mismatch); run again"
  rm -rf "$NAME"; tar -xzf "$NAME.tar.gz"
  (cd "$NAME" && sha256sum -c --quiet SHA256SUMS) || die "bundle contents damaged (SHA256SUMS); run again"
  rm -f "$NAME.tar.gz"
fi
say "installer ready in $BASE_DIR/$NAME"

# ---- other actions ----------------------------------------------------------------------------------
if [[ "$ACTION" != install ]]; then
  args=("$ACTION"); [[ "$ACTION" == resume ]] && args=(install --resume)
  ((VERBOSE)) && args+=(--verbose)
  [[ -e /dev/tty ]] || die "$ACTION asks for confirmation: run it from a terminal"
  say "running: dialcore-install.sh ${args[*]}"
  exec "$BASE_DIR/$NAME/dialcore-install.sh" "${args[@]}" < /dev/tty
fi

# ---- install ----------------------------------------------------------------------------------------
ANS="$(mktemp)"; trap 'rm -f "$ANS"' EXIT; chmod 600 "$ANS"
{
  printf 'DOMAIN=%q\nADMIN_EMAIL=%q\nPUBLIC_IP=%q\nTIMEZONE=%q\n' "$DOMAIN" "$EMAIL" "$PUBLIC_IP" "$TIMEZONE"
  if [[ -n "$CERT" ]]; then printf 'CERT_MODE=%q\n' "$CERT"; fi
  if [[ -n "$EXTRA_ANSWERS" ]]; then cat "$EXTRA_ANSWERS"; fi
} > "$ANS"

args=(install --answers "$ANS")
((INTERACTIVE)) || args+=(--yes)
((VERBOSE)) && args+=(--verbose)
say "installing DialCore $VERSION for https://$DOMAIN (log: /var/log/dialcore-installer.log)"
if ((INTERACTIVE)); then "$BASE_DIR/$NAME/dialcore-install.sh" "${args[@]}" < /dev/tty
else "$BASE_DIR/$NAME/dialcore-install.sh" "${args[@]}" < /dev/null; fi
