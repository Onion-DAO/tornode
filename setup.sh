#!/bin/bash
# OnionDAO bootstrap: puts the OnionDAO CLI in /opt/oniondao and starts the exit node setup.
#
#   curl -fsSL https://raw.githubusercontent.com/Onion-DAO/tornode/main/setup.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/Onion-DAO/tornode/main/setup.sh | sudo bash -s -- --yes
#
# Everything lives in main() so bash reads the whole file before running it when piped.

set -Eeuo pipefail

main() {

	local dir=/opt/oniondao
	local repo=${ONIONDAO_REPO:-https://github.com/Onion-DAO/tornode.git}
	local ref=${ONIONDAO_REF:-}

	[ "$( id -u )" = 0 ] || { echo "Please run as root: curl -fsSL https://raw.githubusercontent.com/Onion-DAO/tornode/main/setup.sh | sudo bash" >&2; exit 1; }
	command -v apt-get > /dev/null || { echo "OnionDAO supports Debian and Ubuntu only" >&2; exit 1; }

	# git and curl are all the bootstrap needs, the installer takes care of the rest
	if ! command -v git > /dev/null || ! command -v curl > /dev/null; then
		echo "Installing git and curl..."
		apt-get -qq -o DPkg::Lock::Timeout=600 update < /dev/null > /dev/null || true
		DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o DPkg::Lock::Timeout=600 install git curl ca-certificates < /dev/null > /dev/null
	fi

	if [ -d "$dir/.git" ]; then
		git -C "$dir" pull --quiet --ff-only < /dev/null || echo "Could not update $dir, continuing with the installed version"
	else
		echo "Downloading OnionDAO to $dir"
		git clone --quiet "$repo" "$dir" < /dev/null
	fi

	# Testing a specific commit or branch
	if [ -n "$ref" ]; then
		git -C "$dir" fetch --quiet origin "$ref" < /dev/null
		git -C "$dir" checkout --quiet -B "$ref" FETCH_HEAD
	fi

	exec "$dir/oniondao.sh" install "$@"

}

main "$@"
