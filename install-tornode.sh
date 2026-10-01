#!/bin/bash
# Sets up (or reconfigures) this server as a Tor exit relay and registers it with the OnionDAO oracle.
# Run through `oniondao install|update`, or by setup.sh on a fresh server. See --help for options.

SELF_DIR=$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )
# shellcheck source=lib/common.sh
source "$SELF_DIR/lib/common.sh"
# shellcheck source=lib/tor.sh
source "$SELF_DIR/lib/tor.sh"
# shellcheck source=lib/register.sh
source "$SELF_DIR/lib/register.sh"
# shellcheck source=lib/autoupdate.sh
source "$SELF_DIR/lib/autoupdate.sh"

# A server that already runs Tor without OnionDAO gets its config replaced, make sure that's intended
confirm_foreign_tor() {

	[ -f "$TORRC" ] && [ ! -f "$CONF_FILE" ] || return 0
	grep -q 'Managed by OnionDAO' "$TORRC" && return 0

	# Pre-1.0 OnionDAO installs had no header but always served this notice
	grep -q "DirPortFrontPage $EXIT_NOTICE" "$TORRC" && return 0

	warn "This server already runs Tor with its own configuration ($TORRC)."
	echo "OnionDAO replaces it with an exit relay setup and keeps a backup at $TORRC.oniondao-backup."
	echo "To only register an existing exit node, use: sudo oniondao register"
	[ "$YES" = yes ] || confirm "Replace the existing Tor configuration?" N || die "Stopped, nothing was changed"

}

main() {

	parse_flags "$@"
	require_root
	take_lock
	echo "=== oniondao install $( date -Is ) ===" >> "$LOG_FILE"

	# Read-only checks first: an unsupported server is left exactly as it was
	preflight

	# Pre-1.0 CLIs start this script from ~/.oniondao, continue from /opt/oniondao
	relocate_to_checkout "$SELF_DIR" install-tornode.sh "$@"

	[ "$AUTO" = yes ] || banner
	load_settings
	confirm_foreign_tor
	collect_settings

	link_cli
	clean_legacy_system
	fix_hostname_resolution
	install_tor_packages
	configure_tor
	setup_unattended_upgrades
	grant_nyx_access
	save_settings
	configure_autoupdate
	remove_legacy_checkouts
	wait_for_tor

	[ "$REGISTER" = yes ] && register_node
	if [ "$AUTO" = yes ]; then ok "OnionDAO update applied"; else finish; fi

}

main "$@"
