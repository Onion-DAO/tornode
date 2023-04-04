#!/bin/bash

PARENT_HOME=$1
PARENT_HOME=${PARENT_HOME:-$HOME}

# Set and create relevant folders
oniondaofolder="$HOME/.oniondao"
binfolder=/usr/local/sbin
rm -rf "$oniondaofolder"
mkdir -p "$oniondaofolder"

# Install dependencies
echo "Installing dependencies..."
sudo apt update -qq &> /dev/null
sudo apt install -y git &> /dev/null

# Write OnionDAO function as executable
echo -e "\nCloning OnionDAO repository to $oniondaofolder"
git clone https://github.com/Onion-DAO/tornode.git "$oniondaofolder" &> /dev/null
echo "Writing executable to $binfolder/oniondao"
sudo cp $oniondaofolder/oniondao.sh $binfolder/oniondao
sudo chmod 755 $binfolder/oniondao
sudo chmod u+x $binfolder/oniondao

# Remove tempfiles
echo -e "\n🎉 OnionDAO installed. Type \"oniondao\" for CLI options."

read -p "Do you want to install Tor on this machine and register it with the OnionDAO Oracle? [Y/n]" INSTALL_TOR
INSTALL_TOR=${INSTALL_TOR:-"y"}

if [ "${INSTALL_TOR,,}" = "y" ]; then
	# Run installation of OnionDAO node
	sudo bash "$oniondaofolder/install-tornode.sh"
else

	read -p "Is this machine already a Tor exit node and do you want to register it with OnionDAO? [Y/n]" REGISTER_ONLY
	REGISTER_ONLY=${REGISTER_ONLY:-"y"}

	# Run installation of OnionDAO node
	sudo bash "$oniondaofolder/register-tornode.sh"

fi