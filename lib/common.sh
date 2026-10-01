#!/bin/bash
# Shared helpers for the OnionDAO tornode scripts. Sourced by the entrypoints, never executed directly.
# shellcheck disable=SC2034 # constants are consumed by the scripts that source this file

set -Eeuo pipefail

## ###############
## Constants
## ###############

ONIONDAO_VERSION="1.0.0"
ONIONDAO_DIR=/opt/oniondao
ONIONDAO_BIN=/usr/local/sbin/oniondao
CONF_DIR=/etc/oniondao
CONF_FILE=$CONF_DIR/oniondao.conf
LOG_FILE=/var/log/oniondao.log
LOCK_FILE=/run/lock/oniondao.lock
ORACLE_URL=${ONIONDAO_ORACLE_URL:-https://oniondao.web.app/api/tor_nodes}

# Releases we test on every change, anything else needs --force
SUPPORTED_CODENAMES="bookworm trixie noble resolute"
SUPPORTED_ARCHS="amd64 arm64"

# Never let apt or dpkg stop to ask questions
export DEBIAN_FRONTEND=noninteractive

## ###############
## Output
## ###############

if [ -t 1 ]; then
	C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_CYAN=$'\e[36m' C_RESET=$'\e[0m'
else
	C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_RESET=''
fi

info() { echo -e "${C_CYAN}$*${C_RESET}"; }
ok() { echo -e "${C_GREEN}✔ $*${C_RESET}"; }
warn() { echo -e "${C_YELLOW}⚠ $*${C_RESET}" >&2; }
# Exit code 3 marks an explained failure, so the ERR trap below stays quiet about it
die() { echo -e "${C_RED}✖ $*${C_RESET}" >&2; exit 3; }
heading() { echo -e "\n${C_CYAN}── $* ──${C_RESET}"; }

# Surface the failing command instead of dying silently under set -e
trap 'rc=$?; [ "$rc" -eq 3 ] && exit 3; echo -e "${C_RED}✖ Unexpected error in ${BASH_SOURCE[0]##*/}:${LINENO}: ${BASH_COMMAND}${C_RESET}\n  Details may be in $LOG_FILE" >&2' ERR

## ###############
## Flags & prompts
## ###############

usage() {
	cat << EOF
Usage: oniondao install|update|register [options]

  -y, --yes           never prompt, read settings from ONIONDAO_* variables or the saved config
  --no-register       set up the node without registering it with the OnionDAO oracle
  --no-unbound        use the system DNS resolver instead of a local unbound resolver
  --no-auto-update    do not enable daily automatic OnionDAO updates
  --force             continue on an untested OS release

Environment: ONIONDAO_EMAIL ONIONDAO_NICKNAME ONIONDAO_WALLET ONIONDAO_BANDWIDTH_TB
             ONIONDAO_EXIT_POLICY=reduced|web ONIONDAO_TWITTER ONIONDAO_TORRC_EXTRA
             ONIONDAO_AUTO_UPDATE=yes|no ONIONDAO_UNBOUND=yes|no
EOF
}

parse_flags() {

	YES=no REGISTER=yes FORCE=no AUTO=no LEGACY_HOME=''
	UNBOUND_FLAG=${ONIONDAO_UNBOUND:-}
	AUTO_UPDATE_FLAG=${ONIONDAO_AUTO_UPDATE:-}

	while [ $# -gt 0 ]; do
		case "$1" in
			-y | --yes) YES=yes ;;
			--no-register) REGISTER=no ;;
			--no-unbound) UNBOUND_FLAG=no ;;
			--no-auto-update) AUTO_UPDATE_FLAG=no ;;
			--force) FORCE=yes ;;
			--auto) AUTO=yes YES=yes REGISTER=no ;;
			-h | --help) usage && exit 0 ;;
			# Pre-1.0 CLIs pass the caller's home directory as the first argument
			/*) LEGACY_HOME=$1 ;;
			*) die "Unknown option: $1 (see --help)" ;;
		esac
		shift
	done

}

# Read an answer from the terminal, which also works when this script is piped into bash
ask() {

	local question=$1 default=${2:-} answer=''

	if [ "$YES" = yes ]; then
		echo "$default"
		return
	fi

	{ : < /dev/tty; } 2> /dev/null || die "No terminal available. Rerun with --yes and ONIONDAO_* variables, see --help"
	read -r -p "$question " answer < /dev/tty
	echo "${answer:-$default}"

}

# confirm "Question" Y|N, succeeds on yes
confirm() {

	local hint='[y/N]'
	[ "$2" = Y ] && hint='[Y/n]'

	local answer
	answer=$( ask "$1 $hint" "$2" )
	[[ "${answer,,}" == y* ]]

}

## ###############
## Validation
## ###############

valid_email() { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
valid_nickname() { [[ "$1" =~ ^[A-Za-z0-9]{1,19}$ ]]; }
valid_wallet() { [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ || "$1" =~ ^[a-z0-9-]+(\.[a-z0-9-]+)*\.eth$ ]]; }
valid_bandwidth() { [[ "$1" =~ ^[1-9][0-9]{0,3}$ ]]; }
valid_policy() { [[ "$1" == reduced || "$1" == web ]]; }
valid_twitter() { [[ -z "$1" || "$1" =~ ^[A-Za-z0-9_]{1,15}$ ]]; }
valid_ipv4() { [[ "$1" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$ ]]; }

## ###############
## Config file
## ###############

# KEY=value lines, parsed (never sourced) so values can't execute code
conf_get() {
	[ -f "$CONF_FILE" ] || return 0
	grep -m1 "^$1=" "$CONF_FILE" | cut -d= -f2- || true
}

conf_set() {

	local key=$1 value=${2//$'\n'/ } tmp
	mkdir -p "$CONF_DIR"
	tmp=$( mktemp "$CONF_FILE.XXXXXX" )

	{
		if [ -f "$CONF_FILE" ]; then grep -v "^$key=" "$CONF_FILE" || true; fi
		echo "$key=$value"
	} > "$tmp"

	chmod 644 "$tmp"
	mv "$tmp" "$CONF_FILE"

}

## ###############
## System checks
## ###############

require_root() {
	[ "$( id -u )" = 0 ] || die "Please run this as root, e.g. with sudo"
}

# One OnionDAO run at a time. Children inherit the lock through ONIONDAO_LOCKED.
take_lock() {

	[ "${ONIONDAO_LOCKED:-}" = 1 ] && return 0
	mkdir -p "${LOCK_FILE%/*}"
	exec 9> "$LOCK_FILE"

	if ! flock -n 9; then
		[ "$AUTO" = yes ] && { echo "Another oniondao run is in progress, skipping"; exit 0; }
		die "Another oniondao run is in progress"
	fi

	export ONIONDAO_LOCKED=1

}

detect_os() {
	[ -r /etc/os-release ] || die "Cannot read /etc/os-release, is this Debian or Ubuntu?"
	OS_ID=$( . /etc/os-release && echo "${ID:-}" )
	OS_CODENAME=$( . /etc/os-release && echo "${VERSION_CODENAME:-}" )
	OS_NAME=$( . /etc/os-release && echo "${PRETTY_NAME:-unknown}" )
	OS_ARCH=$( dpkg --print-architecture 2> /dev/null || uname -m )
}

tor_repo_has_suite() {
	curl -fsSI --max-time 15 "https://deb.torproject.org/torproject.org/dists/$1/Release" > /dev/null 2>&1
}

# Read-only checks. Nothing on the machine may change before these pass.
preflight() {

	detect_os
	[[ "$OS_ID" == debian || "$OS_ID" == ubuntu ]] || die "OnionDAO supports Debian and Ubuntu, found: $OS_NAME"

	if [[ " $SUPPORTED_CODENAMES " != *" $OS_CODENAME "* ]]; then

		if [ -n "$OS_CODENAME" ] && tor_repo_has_suite "$OS_CODENAME"; then

			# Asked once: the answer carries over to the relocated script and is saved for automatic updates
			if ! release_accepted; then
				warn "$OS_NAME is not tested with OnionDAO. Supported: Ubuntu 26.04/24.04 and Debian 13/12."
				confirm "Continue anyway?" N || die "Stopped, nothing was changed"
			fi
			export ONIONDAO_ACCEPTED_RELEASE=$OS_CODENAME

		else
			unsupported_release_help
			exit 1
		fi

	fi

	[[ " $SUPPORTED_ARCHS " == *" $OS_ARCH "* ]] || die "The Tor Project publishes packages for amd64 and arm64 only, this machine is $OS_ARCH"
	[ -d /run/systemd/system ] || die "OnionDAO needs systemd to manage Tor"

	# Tor serves the exit notice on port 80
	if ss -ltnpH 'sport = :80' | grep -qv '"tor"'; then
		die "Port 80 is used by another program (see: ss -ltnp 'sport = :80'). Tor needs it for the exit notice."
	fi

	# Tor recommends 1.5 GB RAM for an exit relay
	local mem_mb
	mem_mb=$( awk '/^MemTotal:/ { print int( $2 / 1024 ) }' /proc/meminfo )
	[ "$mem_mb" -ge 1400 ] || warn "This machine has ${mem_mb} MB RAM, Tor recommends at least 1.5 GB for an exit relay"

	# Tor relays need IPv4, and the oracle verifies nodes over IPv4
	PUBLIC_IP=$( detect_public_ipv4 ) || die "Could not find a public IPv4 address. Tor exit relays (and OnionDAO registration) need IPv4, IPv6-only servers are not supported."

}

# Automatic updates only run on installed nodes, they never stop on a release the node already runs on
release_accepted() {
	[ "$FORCE" = yes ] || [ "$AUTO" = yes ] \
		|| [ "${ONIONDAO_ACCEPTED_RELEASE:-}" = "$OS_CODENAME" ] || [ "$( conf_get ACCEPTED_RELEASE )" = "$OS_CODENAME" ]
}

unsupported_release_help() {

	cat >&2 << EOF
${C_RED}✖ $OS_NAME is not supported: the Tor Project no longer publishes packages for it.${C_RESET}

Nothing on this server was changed. To move your relay to a supported OS (Ubuntu 26.04/24.04, Debian 13/12)
while keeping its identity and reputation:

  1. Back up the relay keys:   sudo tar -czf /root/tor-identity.tgz /var/lib/tor/keys /etc/tor
  2. Copy /root/tor-identity.tgz off this server, then reinstall the server with a supported OS
  3. Run the OnionDAO setup, then restore the keys:
       sudo systemctl stop tor@default
       sudo tar -xzf tor-identity.tgz -C / var/lib/tor/keys
       sudo chown -R debian-tor:debian-tor /var/lib/tor/keys
       sudo systemctl start tor@default
  4. Check the fingerprint is unchanged:   sudo cat /var/lib/tor/fingerprint

Never run the old and the new server with the same keys at the same time.
EOF

}

detect_public_ipv4() {

	local url ip
	for url in https://ipv4.icanhazip.com https://api.ipify.org https://ipv4.seeip.org; do
		ip=$( curl -4 -fsS --max-time 8 "$url" 2> /dev/null | tr -d '[:space:]' ) || continue
		valid_ipv4 "$ip" && echo "$ip" && return 0
	done

	return 1

}

# apt with lock waiting, kept configs and a log instead of terminal noise
apt_get() {

	if ! apt-get -y -q -o DPkg::Lock::Timeout=600 \
		-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
		"$@" < /dev/null >> "$LOG_FILE" 2>&1; then
		tail -n 15 "$LOG_FILE" >&2
		die "apt-get $* failed, full log in $LOG_FILE"
	fi

}

## ###############
## Checkout & legacy installs
## ###############

# Root owns the checkout, safe.directory lets `oniondao status` read it as a normal user
git_od() {
	git -c safe.directory="$ONIONDAO_DIR" -C "$ONIONDAO_DIR" "$@"
}

# Pre-1.0 versions cloned the repo into the caller's ~/.oniondao
legacy_dirs() {

	local homes=( /root ) home
	[ -n "${LEGACY_HOME:-}" ] && homes+=( "$LEGACY_HOME" )
	[ -n "${SUDO_USER:-}" ] && homes+=( "$( getent passwd "$SUDO_USER" | cut -d: -f6 )" )
	for home in /home/*; do homes+=( "$home" ); done

	for home in "${homes[@]}"; do
		[[ -n "$home" && -d "$home/.oniondao/.git" ]] || continue
		git -c safe.directory='*' -C "$home/.oniondao" remote get-url origin 2> /dev/null | grep -q tornode || continue
		readlink -f "$home/.oniondao"
	done | sort -u

}

# Old CLIs run the installer from ~/.oniondao, continue from /opt/oniondao instead
relocate_to_checkout() {

	local self_dir=$1 script=$2
	shift 2
	[ "$self_dir" = "$ONIONDAO_DIR" ] && return 0

	if [ ! -d "$ONIONDAO_DIR/.git" ]; then

		info "Moving OnionDAO to $ONIONDAO_DIR"

		# Clone the exact code that is running, then point it at the real remote.
		# Old checkouts may belong to the user who ran the old CLI, hence safe.directory.
		local origin branch
		origin=$( git -c safe.directory='*' -C "$self_dir" remote get-url origin )
		branch=$( git -c safe.directory='*' -C "$self_dir" symbolic-ref --quiet --short HEAD || echo main )
		git -c safe.directory='*' clone --quiet "$self_dir" "$ONIONDAO_DIR"
		git -C "$ONIONDAO_DIR" remote set-url origin "$origin"
		git -C "$ONIONDAO_DIR" checkout --quiet -B "$branch"

	fi

	exec "$ONIONDAO_DIR/$script" "$@"

}

# Remove pre-1.0 checkouts once their settings live in the config file
remove_legacy_checkouts() {
	local dir
	while read -r dir; do
		[[ -n "$dir" && "$dir" != "$ONIONDAO_DIR" ]] || continue
		rm -rf "$dir"
		ok "Removed old checkout $dir"
	done < <( legacy_dirs )
}

link_cli() {
	# Old versions copied the CLI, newer ones link it so updates apply immediately
	rm -f "$ONIONDAO_BIN"
	ln -s "$ONIONDAO_DIR/oniondao.sh" "$ONIONDAO_BIN"
}

## ###############
## Node settings
## ###############

# Settings come from, in order of priority: ONIONDAO_* variables, the config file, a pre-1.0 install
load_settings() {

	EMAIL=$( conf_get EMAIL ) NICKNAME=$( conf_get NICKNAME ) WALLET=$( conf_get WALLET )
	BANDWIDTH_TB=$( conf_get BANDWIDTH_TB ) EXIT_POLICY=$( conf_get EXIT_POLICY ) TWITTER=$( conf_get TWITTER )
	UNBOUND=$( conf_get UNBOUND ) AUTO_UPDATE=$( conf_get AUTO_UPDATE )

	[ -f "$CONF_FILE" ] || load_legacy_settings

	EMAIL=${ONIONDAO_EMAIL:-$EMAIL}
	NICKNAME=${ONIONDAO_NICKNAME:-$NICKNAME}
	WALLET=${ONIONDAO_WALLET:-$WALLET}
	BANDWIDTH_TB=${ONIONDAO_BANDWIDTH_TB:-$BANDWIDTH_TB}
	EXIT_POLICY=${ONIONDAO_EXIT_POLICY:-$EXIT_POLICY}
	TWITTER=${ONIONDAO_TWITTER:-$TWITTER}
	TWITTER=${TWITTER#@}
	[[ "$WALLET" == *.eth ]] && WALLET=${WALLET,,}

	UNBOUND=${UNBOUND_FLAG:-${UNBOUND:-yes}}

}

# Pre-1.0 installs kept settings in torrc, the exit notice and ~/.oniondao/.oniondaorc
load_legacy_settings() {

	local torrc=/etc/tor/torrc notice=/etc/tor/tor-exit-notice.html rc contact

	if [ -f "$torrc" ]; then
		NICKNAME=$( grep -m1 -oP '^\s*Nickname\s+\K\S+' "$torrc" || true )
		BANDWIDTH_TB=$( grep -m1 -oP '^\s*AccountingMax\s+\K[0-9]+(?=\s*TB)' "$torrc" || true )
		contact=$( grep -m1 -oP '^\s*ContactInfo\s+\K.*' "$torrc" || true )
		EMAIL=$( contact_to_email "$contact" )
		grep -qP '^\s*ReducedExitPolicy\s+1' "$torrc" && EXIT_POLICY=reduced
	fi

	# Both spellings were written by old versions
	[ -f "$notice" ] && WALLET=$( grep -oP '<!-- Onion ?DAO address: \K\S+(?= -->)' "$notice" | tail -n1 || true )

	while read -r rc; do
		[ -f "$rc/.oniondaorc" ] || continue
		TWITTER=$( grep -m1 -oP '^OPERATOR_TWITTER=\K.*' "$rc/.oniondaorc" || true )
		case "$( grep -m1 -oP '^REDUCED_EXIT_POLICY=\K.*' "$rc/.oniondaorc" || true )" in
			[Yy]*) EXIT_POLICY=reduced ;;
			[Nn]*) EXIT_POLICY=web ;;
		esac
	done < <( legacy_dirs )

	return 0

}

# ContactInfo is either a plain address or ContactInfo Information Sharing Spec (email:user[]host)
contact_to_email() {
	local contact=$1
	if [[ "$contact" =~ email:([^[:space:]]+) ]]; then
		contact=${BASH_REMATCH[1]}
		contact=${contact//\[\]/@}
	fi
	echo "$contact"
}

email_to_contact() {
	echo "email:${1//@/[]} ciissversion:3"
}

settings_complete() {
	valid_email "$EMAIL" && valid_nickname "$NICKNAME" && valid_wallet "$WALLET" \
		&& valid_bandwidth "$BANDWIDTH_TB" && valid_policy "$EXIT_POLICY" && valid_twitter "$TWITTER"
}

print_settings() {
	echo "  Wallet (POAP):     ${WALLET:-—}"
	echo "  Node nickname:     ${NICKNAME:-—}"
	echo "  Operator email:    ${EMAIL:-—}"
	echo "  Twitter / X:       ${TWITTER:-—}"
	echo "  Monthly bandwidth: ${BANDWIDTH_TB:-—} TB"
	echo "  Exit policy:       ${EXIT_POLICY:-—}"
}

# prompt_field VAR "Question" validator — re-asks until the answer is valid
prompt_field() {

	local name=$1 question=$2 validator=$3 value

	while true; do
		value=$( ask "$question${!name:+ [${!name}]}:" "${!name}" )
		if $validator "$value"; then
			printf -v "$name" '%s' "$value"
			return 0
		fi
		[ "$YES" = yes ] && die "Invalid value for $name: '$value'"
		warn "That doesn't look right, please try again"
	done

}

collect_settings() {

	# Non-interactive: everything must already be known
	if [ "$YES" = yes ]; then

		BANDWIDTH_TB=${BANDWIDTH_TB:-1} EXIT_POLICY=${EXIT_POLICY:-reduced}
		local missing=()
		valid_email "$EMAIL" || missing+=( "ONIONDAO_EMAIL" )
		valid_nickname "$NICKNAME" || missing+=( "ONIONDAO_NICKNAME (1-19 letters/digits)" )
		valid_wallet "$WALLET" || missing+=( "ONIONDAO_WALLET (0x address or ENS name)" )
		valid_bandwidth "$BANDWIDTH_TB" || missing+=( "ONIONDAO_BANDWIDTH_TB (whole TB)" )
		valid_policy "$EXIT_POLICY" || missing+=( "ONIONDAO_EXIT_POLICY (reduced|web)" )
		valid_twitter "$TWITTER" || missing+=( "ONIONDAO_TWITTER (handle without @)" )
		[ ${#missing[@]} -eq 0 ] || die "Missing or invalid settings: ${missing[*]}"
		return 0

	fi

	if settings_complete; then
		heading "Existing configuration"
		print_settings
		confirm "Keep this configuration?" Y && return 0
	fi

	heading "Tor needs some information"
	BANDWIDTH_TB=${BANDWIDTH_TB:-1}
	prompt_field BANDWIDTH_TB "How many TB may this node use per month?" valid_bandwidth

	echo -e "\nExit policies: ${C_CYAN}reduced${C_RESET} blocks most abuse-prone ports (recommended), ${C_CYAN}web${C_RESET} only allows DNS and http(s)"
	EXIT_POLICY=${EXIT_POLICY:-reduced}
	prompt_field EXIT_POLICY "Exit policy (reduced/web)" valid_policy

	echo -e "\nTor publishes your email so people can reach you about your node. Consider a dedicated address, like yourname+tor@gmail.com."
	prompt_field EMAIL "Your email" valid_email

	echo -e "\nYour nickname is visible on Tor relay search: 1-19 letters and digits."
	prompt_field NICKNAME "Node nickname" valid_nickname

	heading "OnionDAO needs some information"
	prompt_field WALLET "Your wallet address or ENS name (receives POAPs and rewards)" valid_wallet
	[[ "$WALLET" == *.eth ]] && WALLET=${WALLET,,}

	echo -e "\nYour Twitter/X handle is optional, only used to tag you."
	prompt_field TWITTER "Twitter/X handle without @ (optional)" valid_twitter

	heading "Check your information"
	print_settings
	confirm "Continue with these settings?" Y || die "Stopped, nothing was changed"

}

save_settings() {
	local key
	for key in EMAIL NICKNAME WALLET BANDWIDTH_TB EXIT_POLICY TWITTER UNBOUND; do
		conf_set "$key" "${!key}"
	done
	[ -z "${ONIONDAO_ACCEPTED_RELEASE:-}" ] || conf_set ACCEPTED_RELEASE "$ONIONDAO_ACCEPTED_RELEASE"
}

## ###############
## Screens
## ###############

banner() {

	cat << "EOF"

==========================================================

  __   __ _  __  __   __ _    ____   __    __   ____
 /  \ (  ( \(  )/  \ (  ( \  (  _ \ /  \  / _\ (  _ \
(  O )/    / )((  O )/    /   ) __/(  O )/    \ ) __/
 \__/ \_)__)(__)\__/ \_)__)  (__)   \__/ \_/\_/(__)

==========================================================

OnionDAO rewards people who run a Tor exit node. This sets up a Tor exit
relay on this server and registers it with the OnionDAO oracle.

⚠️  OnionDAO is NOT associated with the Tor Project (https://www.torproject.org)
   or with POAP (https://poap.xyz).

🚨 Running a Tor exit node is legal in most places, but check your local rules:
   https://community.torproject.org/relay/community-resources/

EOF

}

finish() {

	cat << EOF

==========================================================

${C_GREEN}🧅 Your OnionDAO Tor exit node is set up.${C_RESET}

  Status:       oniondao status
  Live monitor: sudo nyx
  Exit notice:  http://$PUBLIC_IP/ (put your own template in $CONF_DIR/tor-exit-notice.html)

Recommended: use SSH keys instead of passwords for this server.
Stay up to date in the #onion-dao channel: https://discord.gg/rocketeers

==========================================================
EOF

}
