#!/bin/bash
# OnionDAO CLI: manage this server's Tor exit relay and its OnionDAO registration.
# Installed as /usr/local/sbin/oniondao, a link to /opt/oniondao/oniondao.sh

SELF_DIR=$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )
# shellcheck source=lib/common.sh
source "$SELF_DIR/lib/common.sh"
# shellcheck source=lib/autoupdate.sh
source "$SELF_DIR/lib/autoupdate.sh"

show_help() {
	cat << EOF
🧅 OnionDAO CLI v$ONIONDAO_VERSION — https://github.com/Onion-DAO/tornode

Usage:

  oniondao status                   show this node's configuration and health
  oniondao install [options]        set up a Tor exit relay and register it with OnionDAO
  oniondao update [options]         update OnionDAO and re-apply the configuration
  oniondao register [options]       register an existing Tor exit relay with OnionDAO
  oniondao autoupdate on|off        turn daily automatic updates on or off
  oniondao debug                    print diagnostics to share when asking for help
  oniondao version                  print the CLI version

Options for install/update/register:

$( usage | sed -n '/^  -/,$p' )
EOF
}

# Everything that changes the system runs as root
as_root() {
	[ "$( id -u )" = 0 ] || exec sudo "$ONIONDAO_BIN" "$@"
}

## ###############
## Commands
## ###############

status() {

	parse_flags
	load_settings

	local commit branch remote_head freshness='unknown'
	commit=$( git_od rev-parse --short HEAD 2> /dev/null || echo '?' )
	branch=$( git_od symbolic-ref --quiet --short HEAD 2> /dev/null || echo detached )
	remote_head=$( timeout 5 git_od ls-remote origin "refs/heads/$branch" 2> /dev/null | cut -f1 || true )
	if [ -n "$remote_head" ]; then
		[ "$remote_head" = "$( git_od rev-parse HEAD )" ] && freshness='up to date' || freshness='update available, run: sudo oniondao update'
	fi

	local tor_version tor_state auto_state='off — enable with: sudo oniondao autoupdate on'
	tor_version=$( dpkg-query -W -f '${Version}' tor 2> /dev/null || echo 'not installed' )
	tor_state=$( systemctl is-active tor@default 2> /dev/null || true )
	autoupdate_active && auto_state="on, last run: $( systemctl show oniondao-update.service -p ExecMainExitTimestamp --value 2> /dev/null | grep . || echo never )"

	echo "🧅 OnionDAO v$ONIONDAO_VERSION ($commit on $branch, $freshness)"
	echo
	print_settings
	echo "  Local DNS:         $( [ "$UNBOUND" = yes ] && echo "unbound ($( systemctl is-active unbound 2> /dev/null || true ))" || echo 'system resolver' )"
	echo "  Tor:               $tor_version ($tor_state)"
	echo "  Auto-update:       $auto_state"

}

update() {

	as_root update "$@"
	parse_flags "$@"
	take_lock
	[ -d "$ONIONDAO_DIR/.git" ] || die "$ONIONDAO_DIR is missing, rerun the setup: https://github.com/Onion-DAO/tornode"

	# Pull first, then hand over to the freshly pulled code
	if [ "${ONIONDAO_PULLED:-}" = 1 ]; then
		SELF_UPDATE=updated
	else
		self_update
		if [ "$SELF_UPDATE" = updated ]; then ONIONDAO_PULLED=1 exec "$ONIONDAO_DIR/oniondao.sh" update "$@"; fi
	fi

	# Automatic runs only reconfigure when there is new code
	if [ "$AUTO" = yes ]; then
		case "$SELF_UPDATE" in
			current) echo "OnionDAO is up to date" && exit 0 ;;
			skipped) exit 0 ;;
			failed) die "Automatic update failed, see the messages above" ;;
		esac
	fi

	exec "$ONIONDAO_DIR/install-tornode.sh" "$@"

}

autoupdate() {

	case "${1:-status}" in
		on) as_root autoupdate on && parse_flags && autoupdate_enable ;;
		off) as_root autoupdate off && parse_flags && autoupdate_disable ;;
		status) autoupdate_active && echo "on" || echo "off" ;;
		*) die "Usage: oniondao autoupdate on|off" ;;
	esac

}

debug() {

	as_root debug
	section() { echo -e "\n===== $* ====="; }

	section "System"
	grep -E '^(PRETTY_NAME|VERSION_CODENAME)=' /etc/os-release
	echo "arch: $( dpkg --print-architecture )  kernel: $( uname -r )"
	free -m

	section "OnionDAO"
	echo "v$ONIONDAO_VERSION $( git_od log -1 --format='%h %ci' 2> /dev/null || true )"
	grep -v '^EMAIL=' "$CONF_FILE" 2> /dev/null || echo "no $CONF_FILE"
	systemctl list-timers oniondao-update.timer --no-pager 2> /dev/null || true

	section "Tor"
	dpkg-query -W -f '${Version}\n' tor 2> /dev/null || echo "tor not installed"
	systemctl status tor@default --no-pager -n 0 2> /dev/null || true
	journalctl -u tor@default -n 40 --no-pager 2> /dev/null || true

	section "Listening ports"
	ss -ltnp

	section "torrc (ContactInfo hidden)"
	sed 's/^ContactInfo .*/ContactInfo [hidden]/' /etc/tor/torrc 2> /dev/null || true
	cat /etc/tor/torrc.d/*.conf 2> /dev/null || true

	section "Last install log lines"
	tail -n 30 "$LOG_FILE" 2> /dev/null || true

}

## ###############
## Entry
## ###############

command=${1:-help}
[ $# -gt 0 ] && shift

case "$command" in
	help | -h | --help) show_help ;;
	version | -v | --version) echo "🧅 OnionDAO v$ONIONDAO_VERSION" ;;
	status) status ;;
	install) as_root install "$@" && exec "$SELF_DIR/install-tornode.sh" "$@" ;;
	register) as_root register "$@" && exec "$SELF_DIR/register-tornode.sh" "$@" ;;
	update) update "$@" ;;
	autoupdate) autoupdate "$@" ;;
	debug) debug ;;
	*) die "Unknown command: $command, see: oniondao help" ;;
esac
