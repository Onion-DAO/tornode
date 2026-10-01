#!/bin/bash
# Daily automatic updates of the OnionDAO code through a systemd timer. Sourced after lib/common.sh.

UPDATE_SERVICE=/etc/systemd/system/oniondao-update.service
UPDATE_TIMER=/etc/systemd/system/oniondao-update.timer

autoupdate_active() {
	systemctl is-enabled --quiet oniondao-update.timer 2> /dev/null
}

autoupdate_enable() {

	cat > "$UPDATE_SERVICE" << EOF
[Unit]
Description=OnionDAO automatic update
Documentation=https://github.com/Onion-DAO/tornode
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$ONIONDAO_BIN update --auto
Nice=10
EOF

	# Spread nodes over the day so a release doesn't hit every exit at once
	cat > "$UPDATE_TIMER" << EOF
[Unit]
Description=Daily OnionDAO automatic update

[Timer]
OnCalendar=daily
RandomizedDelaySec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF

	systemctl daemon-reload
	systemctl enable --now oniondao-update.timer > /dev/null 2>&1
	conf_set AUTO_UPDATE yes
	ok "Automatic OnionDAO updates enabled (daily, see: journalctl -u oniondao-update)"

}

autoupdate_disable() {
	systemctl disable --now oniondao-update.timer > /dev/null 2>&1 || true
	conf_set AUTO_UPDATE no
	ok "Automatic OnionDAO updates disabled"
}

# Install and update both land here. On by default, a saved opt-out is respected in unattended runs.
configure_autoupdate() {

	# Opting out is always saved, so later unattended runs respect it
	if [ "$AUTO_UPDATE_FLAG" = no ]; then
		if autoupdate_active; then autoupdate_disable; else conf_set AUTO_UPDATE no; fi
		return 0
	fi

	if autoupdate_active; then
		autoupdate_enable > /dev/null # refresh the unit files
		return 0
	fi

	if [ "$YES" = yes ]; then
		[ "$AUTO_UPDATE_FLAG" = yes ] || [ "$AUTO_UPDATE" != no ] || return 0
		autoupdate_enable
		return 0
	fi

	if confirm "Enable automatic OnionDAO updates?" Y; then
		autoupdate_enable
	else
		conf_set AUTO_UPDATE no
		info "Skipped. Enable later with: sudo oniondao autoupdate on"
	fi

}

# Fast-forward the checkout to its remote branch. Sets SELF_UPDATE to updated|current|skipped|failed.
# shellcheck disable=SC2034 # SELF_UPDATE is read by oniondao.sh
self_update() {

	SELF_UPDATE=failed
	local branch before

	branch=$( git -C "$ONIONDAO_DIR" symbolic-ref --quiet --short HEAD ) || {
		warn "$ONIONDAO_DIR is not on a branch, skipping the code update"
		SELF_UPDATE=skipped
		return 0
	}

	if ! git -C "$ONIONDAO_DIR" diff --quiet HEAD; then
		warn "$ONIONDAO_DIR has local changes, skipping the code update"
		SELF_UPDATE=skipped
		return 0
	fi

	before=$( git -C "$ONIONDAO_DIR" rev-parse HEAD )

	if ! timeout 120 git -C "$ONIONDAO_DIR" fetch --quiet origin "$branch"; then
		warn "Could not fetch updates from $( git -C "$ONIONDAO_DIR" remote get-url origin )"
		return 0
	fi

	# Never merge or rewrite: anything but a fast-forward is left alone
	if ! git -C "$ONIONDAO_DIR" merge --quiet --ff-only FETCH_HEAD > /dev/null 2>&1; then
		warn "$ONIONDAO_DIR has diverged from origin/$branch, not updating"
		return 0
	fi

	if [ "$before" = "$( git -C "$ONIONDAO_DIR" rev-parse HEAD )" ]; then
		SELF_UPDATE=current
	else
		SELF_UPDATE=updated
		ok "OnionDAO updated to $( git -C "$ONIONDAO_DIR" log -1 --format='%h %s' )"
	fi

}
