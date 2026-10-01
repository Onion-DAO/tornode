#!/bin/bash

## ###############
## Variables
## ###############
oniondaofolder="$HOME/.oniondao/"
binfolder=/usr/local/sbin
visudo_path=/private/etc/sudoers.d/tordao
version='0.0.1'

# CLI help message
helpmessage="
OnionDAO CLI utility v$version.
Authors: @actuallymentor
Docs: https://github.com/Onion-DAO/tornode/

Usage: 

  oniondao help
    output (this) oniondao help message

  oniondao version
    output the OnionDAO cli version

  oniondao status
    output your current configuration

  oniondao install
    set up and register a Tor exit node and notify the OnionDAO oracle

	oniondao register
    register an existing Tor node with the OnionDAO oracle

  oniondao update
    update your OnionDAO node to the lasest CLI and configuration


"

# Get parameters
action=$1

## ###############
## Helpers
## ###############

function log() {

	echo -e "$(date +%T) - $1"

}


## ###############
## Actions
## ###############

# Help message 
if [ -z "$action" ]; then
	echo -e "$helpmessage"
	exit 0
fi

if [[ "$action" == "help" ]]; then
	echo -e "$helpmessage"
	exit 0
fi

# Visudo message
if [[ "$action" == "version" ]]; then
	echo "🧅 OnionDAO version v$version"
	exit 0
fi

# Update script trigger
if [[ "$action" == "status" ]]; then

	echo "🧅 OnionDAO version v$version"

	echo -e "\n\n----------------------------------------"
  echo -e "Your existing configurations:"
  echo -e "----------------------------------------\n\n"

  NODE_NICKNAME=$( grep -Po "(?<=Nickname )(.*)" /etc/tor/torrc 2> /dev/null )
  NODE_BANDWIDTH=$( grep -Po "(?<=AccountingMax )(.*)(?= TB)" /etc/tor/torrc 2> /dev/null )
  OPERATOR_EMAIL=$( grep -Po "(?<=ContactInfo )(.*)" /etc/tor/torrc 2> /dev/null )
  OPERATOR_WALLET=$( grep -Po "(?<= address: )(.*)(?= -->)" /etc/tor/tor-exit-notice.html 2> /dev/null )
  OPERATOR_TWITTER=$( grep -Po "(?<=OPERATOR_TWITTER=)(.*)" "$oniondaofolder/.oniondaorc" 2> /dev/null )

  echo "POAP wallet: $OPERATOR_WALLET"
  echo "Node nickname: $NODE_NICKNAME"
  echo "Operator email: $OPERATOR_EMAIL"
  echo "Operator twitter: $OPERATOR_TWITTER"
  echo "Monthly bandwidth limit: $NODE_BANDWIDTH TB"

	exit 0
fi

# Installation script trigger
if [[ "$action" == "install" ]]; then
	cd "$oniondaofolder"
	git pull &> /dev/null
	sudo bash "./install-tornode.sh" "$HOME"
	exit 0
fi

# Update script trigger
if [[ "$action" == "update" ]]; then
	cd "$oniondaofolder"
	git pull &> /dev/null
	sudo bash "./install-tornode.sh" "$HOME"
	exit 0
fi

# Update script trigger
if [[ "$action" == "register" ]]; then
	cd "$oniondaofolder"
	git pull &> /dev/null
	sudo bash "./register-tornode.sh" "$HOME"
	exit 0
fi

if [[ "$action" == "debug" ]]; then
	
	log "\nSystem data:"
	cat /etc/os-release
	free -m
	cat /proc/cpuinfo

	log "\nOniondao status:"
	oniondao status

	log "\nTor status:"
	service tor status

	log "\nTor binary:"
	which tor

	log "\nPorts in use:"
	sudo netstat -lp

	log "\nTor config:"
	cat /etc/tor/torrc

	exit 0
fi
