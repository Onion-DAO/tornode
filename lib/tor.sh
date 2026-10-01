#!/bin/bash
# Tor relay setup: packages, configuration, exit notice, DNS and updates. Sourced after lib/common.sh.

TOR_KEY_FINGERPRINT=A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
TOR_KEYRING=/usr/share/keyrings/deb.torproject.org-keyring.gpg
TOR_SOURCES=/etc/apt/sources.list.d/tor.sources
TORRC=/etc/tor/torrc
TORRC_DIR=/etc/tor/torrc.d
EXIT_NOTICE=/etc/tor/tor-exit-notice.html
TOR_RESOLV=/etc/tor/resolv.conf

## ###############
## Packages
## ###############

install_tor_packages() {

	heading "Installing Tor"

	# Bootstrap tools first: minimal images (e.g. Debian 12 cloud) ship without gnupg
	info "Updating package lists..."
	apt_get update
	apt_get install ca-certificates curl gnupg

	add_tor_repository
	apt_get update

	local packages=( tor deb.torproject.org-keyring nyx jq unattended-upgrades )
	# dns-root-data is only a Recommends of unbound, but DNSSEC validation fails without it
	[ "$UNBOUND" = yes ] && packages+=( unbound dns-root-data )
	info "Installing ${packages[*]}..."
	apt_get install "${packages[@]}"

	# 0.4.8 is end-of-life and being removed from the network
	local version
	version=$( dpkg-query -W -f '${Version}' tor )
	dpkg --compare-versions "$version" ge 0.4.9 || die "Tor $version is too old, expected 0.4.9 or newer from deb.torproject.org"
	ok "Tor $version installed"

}

# Official Tor Project repository: https://support.torproject.org/little-t-tor/getting-started/installing/
add_tor_repository() {

	if [ ! -s "$TOR_KEYRING" ]; then

		local gpg_home key_file
		gpg_home=$( mktemp -d ) key_file=$( mktemp )

		curl -fsSL "https://deb.torproject.org/torproject.org/$TOR_KEY_FINGERPRINT.asc" \
			| gpg --homedir "$gpg_home" --dearmor > "$key_file" \
			|| die "Could not download the Tor Project signing key"

		# Only trust the key we expect
		gpg --homedir "$gpg_home" --show-keys --with-colons "$key_file" 2> /dev/null \
			| grep -q "^fpr:.*:$TOR_KEY_FINGERPRINT:" \
			|| die "The downloaded Tor Project key does not match fingerprint $TOR_KEY_FINGERPRINT"

		install -m 644 "$key_file" "$TOR_KEYRING"
		rm -rf "$gpg_home" "$key_file"

	fi

	cat > "$TOR_SOURCES" << EOF
Types: deb
URIs: https://deb.torproject.org/torproject.org/
Suites: $OS_CODENAME
Components: main
Signed-By: $TOR_KEYRING
EOF

	ok "Tor Project repository added for $OS_CODENAME"

}

## ###############
## Pre-1.0 installs
## ###############

# Undo what old versions did to the system, safe to run on every install
clean_legacy_system() {

	# One-line focal source trusted through apt-key
	if [ -f /etc/apt/sources.list.d/tor.list ] && grep -q torproject /etc/apt/sources.list.d/tor.list; then
		rm -f /etc/apt/sources.list.d/tor.list
		ok "Removed old Tor apt source"
	fi
	if command -v apt-key > /dev/null && apt-key list 2> /dev/null | tr -d ' ' | grep -q "$TOR_KEY_FINGERPRINT"; then
		apt-key del "$TOR_KEY_FINGERPRINT" > /dev/null 2>&1 || true
		ok "Removed old apt-key trust for the Tor Project"
	fi

	# Old versions installed a system-wide "never install recommended packages" rule
	local norecommends=/etc/apt/apt.conf.d/40norecommends
	if [ -f "$norecommends" ] && [ "$( tr -d '[:space:]' < "$norecommends" )" = 'APT{Install-Recommends"false";Install-Suggests"false";};' ]; then
		rm -f "$norecommends"
		ok "Removed the old system-wide no-recommends apt rule"
	fi

	# Old versions replaced the distro's unattended-upgrades config. It is ucf-managed, so restore it through ucf.
	local uu=/etc/apt/apt.conf.d/50unattended-upgrades
	if [ -f "$uu" ] && grep -q 'origin=TorProject' "$uu"; then
		rm -f "$uu"
		UCF_FORCE_CONFFMISS=1 apt_get install --reinstall unattended-upgrades
		if [ -f "$uu" ]; then ok "Restored the distribution's unattended-upgrades config"; else warn "Could not restore $uu"; fi
	fi

}

## ###############
## Configuration
## ###############

write_exit_notice() {

	# Operators can provide their own template, e.g. without the US-specific sections
	local template=$CONF_DIR/tor-exit-notice.html
	[ -f "$template" ] || template=/usr/share/doc/tor/tor-exit-notice.html
	[ -f "$template" ] || template=$ONIONDAO_DIR/assets/tor-exit-notice.html

	local html tmp
	html=$( < "$template" )
	html=${html//FIXME_YOUR_EMAIL_ADDRESS/"$EMAIL"}
	html=${html//FIXME_DNS_NAME/"$PUBLIC_IP"}

	# The oracle reads the wallet from this comment to verify node ownership
	tmp=$( mktemp )
	printf '%s\n<!-- OnionDAO address: %s -->\n' "$html" "$WALLET" > "$tmp"
	install -m 644 "$tmp" "$EXIT_NOTICE"
	rm -f "$tmp"

}

render_torrc() {

	cat << EOF
## Managed by OnionDAO, changes here are overwritten by \`oniondao update\`.
## Add your own options in $TORRC_DIR/*.conf instead.

SocksPort 0
ORPort 9001
Nickname $NICKNAME
ContactInfo $( email_to_contact "$EMAIL" )

# Exit relay with a notice page, the OnionDAO oracle verifies your wallet through it
ExitRelay 1
IPv6Exit 1
DirPort 80
DirPortFrontPage $EXIT_NOTICE
EOF

	if [ "$EXIT_POLICY" = reduced ]; then
		echo "ReducedExitPolicy 1"
	else
		printf 'ExitPolicy accept *:%s\n' 53 80 443
		echo "ExitPolicy reject *:*"
	fi

	cat << EOF

# Monthly bandwidth cap
AccountingStart month 1 00:00
AccountingMax $BANDWIDTH_TB TB

# Local access for nyx
ControlPort 9051
CookieAuthentication 1
DisableDebuggerAttachment 0
EOF

	[ "$UNBOUND" = yes ] && printf '\n# Resolve exit traffic through the local unbound resolver\nServerDNSResolvConfFile %s\n' "$TOR_RESOLV"

	printf '\n%%include %s/\n' "$TORRC_DIR"

}

configure_tor() {

	heading "Configuring Tor"

	mkdir -p "$TORRC_DIR"
	[ -n "${ONIONDAO_TORRC_EXTRA:-}" ] && printf '%s\n' "$ONIONDAO_TORRC_EXTRA" > "$TORRC_DIR/50-oniondao-extra.conf"

	if [ "$UNBOUND" = yes ]; then
		systemctl enable unbound > /dev/null 2>&1
		systemctl restart unbound > /dev/null 2>&1 || true
		sleep 3
		if ! systemctl is-active --quiet unbound; then
			journalctl -u unbound -n 10 --no-pager >&2 || true
			die "The local unbound resolver did not start (is port 53 taken?). Rerun with --no-unbound to use the system resolver"
		fi
		echo "nameserver 127.0.0.1" > "$TOR_RESOLV"
	else
		rm -f "$TOR_RESOLV"
	fi

	write_exit_notice

	local new_torrc
	new_torrc=$( mktemp )
	render_torrc > "$new_torrc"
	chmod 644 "$new_torrc"

	# Validate exactly like the systemd unit runs tor
	if ! tor --defaults-torrc /usr/share/tor/tor-service-defaults-torrc -f "$new_torrc" --verify-config >> "$LOG_FILE" 2>&1; then
		tail -n 10 "$LOG_FILE" >&2
		die "Tor rejected the generated configuration, nothing was changed"
	fi

	[ -f "$TORRC" ] && cp -p "$TORRC" "$TORRC.oniondao-backup"
	mv "$new_torrc" "$TORRC"
	ok "Tor configuration written to $TORRC"

	systemctl enable tor > /dev/null 2>&1
	if ! systemctl restart tor@default; then
		warn "Tor failed to start, restoring the previous configuration"
		[ -f "$TORRC.oniondao-backup" ] && cp -p "$TORRC.oniondao-backup" "$TORRC"
		systemctl restart tor@default || true
		journalctl -u tor@default -n 20 --no-pager >&2 || true
		die "Tor did not start with the new configuration"
	fi

}

# The exit notice on port 80 is what the oracle checks, wait until it is served
wait_for_tor() {

	info "Waiting for Tor to come online, this can take a few minutes..."

	local waited=0
	until curl -fsS --max-time 3 http://127.0.0.1/ > /dev/null 2>&1; do

		systemctl is-active --quiet tor@default || { journalctl -u tor@default -n 20 --no-pager >&2 || true; die "Tor stopped unexpectedly"; }
		[ "$waited" -ge 300 ] && die "Tor did not serve the exit notice within 5 minutes, check: journalctl -u tor@default"

		[ -t 1 ] && printf '.'
		sleep 5
		waited=$(( waited + 5 ))

	done

	[ -t 1 ] && echo
	ok "Tor is running and serving the exit notice on port 80"

}

## ###############
## Updates
## ###############

# Keep Tor itself up to date through unattended-upgrades, next to the distro security updates
setup_unattended_upgrades() {

	local dropin=/etc/apt/apt.conf.d/51oniondao-tor

	# Ubuntu matches the Tor repo by suite, Debian's Tor suites are named stable/oldstable so match by origin
	# shellcheck disable=SC2016 # ${distro_codename} is expanded by unattended-upgrades
	if [ "$OS_ID" = ubuntu ]; then
		echo 'Unattended-Upgrade::Allowed-Origins { "TorProject:${distro_codename}"; };' > "$dropin"
	else
		echo 'Unattended-Upgrade::Origins-Pattern { "origin=TorProject"; };' > "$dropin"
	fi

	[ -f /etc/apt/apt.conf.d/20auto-upgrades ] || printf '%s\n' \
		'APT::Periodic::Update-Package-Lists "1";' \
		'APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades

	ok "Automatic Tor and security updates enabled"

}

# nyx reads Tor's control cookie, which belongs to the debian-tor group
grant_nyx_access() {
	local user=${SUDO_USER:-}
	[ -n "$user" ] && [ "$user" != root ] && usermod -aG debian-tor "$user" && ok "Added $user to the debian-tor group for nyx (log in again to use it)"
	return 0
}

# Some VPS images don't resolve their own hostname, which makes sudo slow
fix_hostname_resolution() {
	local host
	host=$( hostname )
	grep -qw -- "$host" /etc/hosts || echo "127.0.1.1 $host" >> /etc/hosts
}
