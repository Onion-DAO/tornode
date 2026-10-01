#!/bin/bash
# Registration with the OnionDAO oracle. Sourced after lib/common.sh.

register_node() {

	heading "Registering node with the OnionDAO oracle"

	local policy=N payload response status body
	[ "$EXIT_POLICY" = reduced ] && policy=Y

	# jq escapes every value, so quotes in user input can't break the request
	payload=$( jq -cn \
		--arg ip "$PUBLIC_IP" \
		--arg email "$EMAIL" \
		--arg bandwidth "$BANDWIDTH_TB" \
		--arg reduced_exit_policy "$policy" \
		--arg node_nickname "$NICKNAME" \
		--arg wallet "$WALLET" \
		--arg twitter "$TWITTER" \
		'{ $ip, $email, $bandwidth, $reduced_exit_policy, $node_nickname, $wallet }
		+ if ( $twitter | length ) > 3 then { $twitter } else {} end' )

	# The oracle checks ports 80 and 9001 from the outside, which can take a while
	response=$( curl -sS --max-time 120 -H 'Content-Type: application/json' --data-binary "$payload" \
		-w '\n%{http_code}' "$ORACLE_URL" ) || die "Could not reach the OnionDAO oracle at $ORACLE_URL"

	status=${response##*$'\n'}
	body=${response%$'\n'*}

	# Older oracle versions answer HTTP 200 with a 🛑 message on rejection
	if [[ "$status" == 2* && "$body" != *🛑* ]]; then
		ok "$body"
	else
		die "Registration failed (HTTP $status): $body"
	fi

}
