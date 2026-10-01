#!/bin/bash
# Recreates a node installed with the 2022 OnionDAO scripts, including everything they changed on the system.
# Run as root on Ubuntu 24.04 (apt-key still exists there) from a full checkout of this repo.

set -euo pipefail

repo=$( cd "$( dirname "$0" )/.." && pwd )
fixtures=$repo/test/fixtures
export DEBIAN_FRONTEND=noninteractive

# Tor from the distro, configured the 2022 way
apt-get update -qq
apt-get install -y -qq tor > /dev/null
install -m 644 "$fixtures/torrc-2022" /etc/tor/torrc
sed "s/FIXME_YOUR_EMAIL_ADDRESS/temporaty-test@palokaj.co/" "$repo/assets/tor-exit-notice.html" > /etc/tor/tor-exit-notice.html
echo "<!-- Onion DAO address: mentor.eth -->" >> /etc/tor/tor-exit-notice.html
systemctl restart tor@default

# apt changes of the 2022 scripts: focal source trusted through apt-key, replaced configs
echo "deb https://deb.torproject.org/torproject.org focal main" > /etc/apt/sources.list.d/tor.list
curl -fsSL https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | apt-key add - > /dev/null 2>&1
install -m 644 "$fixtures/50unattended-upgrades.flxn" /etc/apt/apt.conf.d/50unattended-upgrades
install -m 644 "$fixtures/40norecommends.flxn" /etc/apt/apt.conf.d/40norecommends

# The 2022 checkout in root's home at the last 2022 commit, plus the copied CLI
git clone -q "$repo" /root/.oniondao
git -C /root/.oniondao checkout -q -B main ebff1c3
git -C /root/.oniondao branch -q --set-upstream-to=origin/main main
printf 'OPERATOR_TWITTER=\nREDUCED_EXIT_POLICY=N\n' > /root/.oniondao/.oniondaorc
install -m 755 "$fixtures/oniondao-cli-2022.sh" /usr/local/sbin/oniondao

# Keep the test relay out of the Tor network once the new torrc includes torrc.d
mkdir -p /etc/tor/torrc.d
echo "PublishServerDescriptor 0" > /etc/tor/torrc.d/50-oniondao-extra.conf

echo "Seeded a 2022 OnionDAO node"
