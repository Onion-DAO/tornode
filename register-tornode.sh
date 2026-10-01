#!/bin/bash
# Registers this Tor exit relay with the OnionDAO oracle, also for exits that were set up without OnionDAO.
# Run through `oniondao register`. See --help for options.

SELF_DIR=$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )
# shellcheck source=lib/common.sh
source "$SELF_DIR/lib/common.sh"
# shellcheck source=lib/tor.sh
source "$SELF_DIR/lib/tor.sh"
# shellcheck source=lib/register.sh
source "$SELF_DIR/lib/register.sh"

# The oracle reads the wallet from the page Tor serves on port 80
publish_wallet() {

	if grep -q 'Managed by OnionDAO' "$TORRC" 2> /dev/null; then
		write_exit_notice
	else

		local page tmp
		page=$( grep -m1 -oP '^\s*DirPortFrontPage\s+\K\S+' "$TORRC" 2> /dev/null || true )
		[[ -n "$page" && -f "$page" ]] || die "Registration needs Tor to serve an exit notice on port 80 (DirPort 80 + DirPortFrontPage in $TORRC). Run: sudo oniondao install"

		tmp=$( mktemp )
		grep -vP '<!-- Onion ?DAO address: ' "$page" > "$tmp" || true
		echo "<!-- OnionDAO address: $WALLET -->" >> "$tmp"
		install -m 644 "$tmp" "$page"
		rm -f "$tmp"

	fi

	systemctl reload tor@default
	ok "Exit notice now names $WALLET"

}

main() {

	parse_flags "$@"
	require_root
	take_lock
	echo "=== oniondao register $( date -Is ) ===" >> "$LOG_FILE"

	preflight
	relocate_to_checkout "$SELF_DIR" register-tornode.sh "$@"

	[ "$YES" = yes ] || banner
	command -v jq > /dev/null || apt_get install jq
	load_settings
	EXIT_POLICY=${EXIT_POLICY:-reduced} BANDWIDTH_TB=${BANDWIDTH_TB:-1}

	# Tor settings come from torrc or the config, only the OnionDAO details are asked
	if [ "$YES" = no ]; then
		heading "OnionDAO needs some information"
		echo "Node nickname, email and bandwidth come from $TORRC, edit them there (or run: sudo oniondao install)."
		if ! { valid_wallet "$WALLET" && confirm "Keep $WALLET as your wallet?" Y; }; then
			prompt_field WALLET "Your wallet address or ENS name" valid_wallet
		fi
		[[ "$WALLET" == *.eth ]] && WALLET=${WALLET,,}
		prompt_field TWITTER "Twitter/X handle without @ (optional)" valid_twitter
		valid_email "$EMAIL" || prompt_field EMAIL "Operator email" valid_email
		valid_nickname "$NICKNAME" || prompt_field NICKNAME "Node nickname" valid_nickname
	fi
	collect_settings_check

	publish_wallet
	[ -f "$CONF_FILE" ] && save_settings
	wait_for_tor
	register_node

}

# Same rules as an install, without asking again
collect_settings_check() {
	local yes=$YES
	YES=yes
	collect_settings
	YES=$yes
}

main "$@"
