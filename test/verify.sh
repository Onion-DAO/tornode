#!/bin/bash
# Asserts that a server set up by OnionDAO is healthy. Used on test droplets and in CI.
#
#   sudo EXPECT_WALLET=mentor.eth EXPECT_POLICY=reduced EXPECT_AUTO_UPDATE=yes EXPECT_UNBOUND=yes test/verify.sh

set -uo pipefail

EXPECT_WALLET=${EXPECT_WALLET:-mentor.eth}
EXPECT_POLICY=${EXPECT_POLICY:-reduced}
EXPECT_AUTO_UPDATE=${EXPECT_AUTO_UPDATE:-yes}
EXPECT_UNBOUND=${EXPECT_UNBOUND:-yes}
failures=0

check() {
	local name=$1
	shift
	if "$@" > /dev/null 2>&1; then
		echo "✔ $name"
	else
		echo "✖ $name"
		failures=$(( failures + 1 ))
	fi
}

# Ask Tor's control port for one value, authenticating with the cookie file
tor_getinfo() {
	local cookie
	cookie=$( od -An -tx1 /run/tor/control.authcookie | tr -d ' \n' )
	exec 3<> /dev/tcp/127.0.0.1/9051
	printf 'AUTHENTICATE %s\r\nGETINFO %s\r\nQUIT\r\n' "$cookie" "$1" >&3
	timeout 5 cat <&3
	exec 3>&-
}

policy=$( tor_getinfo exit-policy/full | tr ',' '\n' )

echo "== Tor"
check "tor is 0.4.9 or newer" dpkg --compare-versions "$( dpkg-query -W -f '${Version}' tor )" ge 0.4.9
check "tor comes from deb.torproject.org" bash -c "apt-cache policy tor | grep -A1 '^ \*\*\*' | grep -q deb.torproject.org"
check "repository uses deb822 + signed-by" grep -q 'Signed-By: /usr/share/keyrings/deb.torproject.org-keyring.gpg' /etc/apt/sources.list.d/tor.sources
check "tor@default is active" systemctl is-active --quiet tor@default
check "torrc is valid" tor --defaults-torrc /usr/share/tor/tor-service-defaults-torrc -f /etc/tor/torrc --verify-config
check "ORPort 9001 on IPv4" bash -c "ss -ltnH 'sport = :9001' | grep -q '0.0.0.0:9001'"
# CI runners and containers often run without IPv6
if [ -s /proc/net/if_inet6 ]; then
	check "ORPort 9001 on IPv6" bash -c "ss -ltnH 'sport = :9001' | grep -q '\[::\]:9001'"
fi
check "exit notice served on port 80" curl -fsS --max-time 5 http://127.0.0.1/
check "exit notice names $EXPECT_WALLET" bash -c "curl -fsS --max-time 5 http://127.0.0.1/ | grep -qF '<!-- OnionDAO address: $EXPECT_WALLET -->'"
check "exit notice has no FIXME_ placeholders" bash -c "! curl -fsS --max-time 5 http://127.0.0.1/ | grep -q 'FIXME_'"

echo "== Exit policy ($EXPECT_POLICY)"
check "policy rejects SMTP (25) on IPv4" bash -c "grep -q 'reject \*:25\b\|reject \*:\*' <<< '$policy'"
check "policy accepts HTTPS (443) on IPv4" bash -c "grep -q 'accept \*:443' <<< '$policy'"
check "policy accepts HTTPS (443) on IPv6" bash -c "grep -q 'accept6 \*:443' <<< '$policy'"
if [ "$EXPECT_POLICY" = reduced ]; then
	check "reduced policy accepts SSH (22)" bash -c "grep -q 'accept \*:20-23' <<< '$policy'"
else
	check "web policy does not accept SSH (22)" bash -c "! grep -q 'accept \*:2[0-2]' <<< '$policy'"
	check "web policy ends with reject *:*" bash -c "grep -q 'reject \*:\*' <<< '$policy'"
fi

echo "== DNS"
if [ "$EXPECT_UNBOUND" = yes ]; then
	check "unbound is active" systemctl is-active --quiet unbound
	check "tor resolves through unbound" grep -q '^ServerDNSResolvConfFile /etc/tor/resolv.conf' /etc/tor/torrc
	check "unbound answers with DNSSEC" bash -c "dig +time=5 @127.0.0.1 torproject.org | grep -q 'flags:.* ad'"
else
	check "tor uses the system resolver" bash -c "! grep -q ServerDNSResolvConfFile /etc/tor/torrc"
fi

echo "== Updates"
uu_origins=$( unattended-upgrade --dry-run --debug 2>&1 | grep -i 'allowed origins' )
check "unattended-upgrades allows the Tor Project" grep -qi torproject <<< "$uu_origins"
check "unattended-upgrades still allows distro security" grep -qi security <<< "$uu_origins"
if [ "$EXPECT_AUTO_UPDATE" = yes ]; then
	check "oniondao auto-update timer enabled" systemctl is-enabled --quiet oniondao-update.timer
else
	check "oniondao auto-update timer disabled" bash -c "! systemctl is-enabled --quiet oniondao-update.timer"
fi

echo "== OnionDAO"
check "CLI links to /opt/oniondao" bash -c "[ \"\$( readlink -f /usr/local/sbin/oniondao )\" = /opt/oniondao/oniondao.sh ]"
check "config saved" grep -q "^WALLET=$EXPECT_WALLET$" /etc/oniondao/oniondao.conf
check "oniondao status works" /usr/local/sbin/oniondao status
check "no legacy tor.list" test ! -e /etc/apt/sources.list.d/tor.list
check "no legacy checkout in /root" test ! -e /root/.oniondao
check "50unattended-upgrades is the distro's" bash -c "! grep -q origin=TorProject /etc/apt/apt.conf.d/50unattended-upgrades"

echo
if [ "$failures" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$failures CHECK(S) FAILED"; fi
exit "$failures"
