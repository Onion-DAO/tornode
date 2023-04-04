#!/bin/bash

# Global config
BIN_FOLDER=/usr/local/sbin
ONIONDAO_PATH="$HOME/.oniondao"
DOCKER_COMPOSE_PATH="$ONIONDAO_PATH/docker-composition"

## ###############
## Force latest version
## ###############
cd "$ONIONDAO_PATH"
git pull &> /dev/null
sudo cp $ONIONDAO_PATH/oniondao.sh $BIN_FOLDER/oniondao
sudo chmod 755 $BIN_FOLDER/oniondao
sudo chmod u+x $BIN_FOLDER/oniondao

## ###############
## Tor POAP config
## ###############

cat << "EOF"

==========================================================

__   __ _  __  __   __ _    ____   __    __   ____ 
 /  \ (  ( \(  )/  \ (  ( \  (  _ \ /  \  / _\ (  _ \
(  O )/    / )((  O )/    /   ) __/(  O )/    \ ) __/
 \__/ \_)__)(__)\__/ \_)__)  (__)   \__/ \_/\_/(__)


==========================================================

Onion POAP is an Onion DAO initiative that hands out POAP tokens to people who run a Tor exit node.

This is a setup script that will install a Tor exit node & register that node with Tor POAP.

⚠️  Disclaimer: Tor POAP is *NOT* associated with the Tor project. To learn about the Tor project, go to: https://www.torproject.org/.

⚠️  Disclaimer: Tor POAP is *NOT* associated with POAP. To learn more about POAP, go to https://poap.xyz/.

🚨  IMPORTANT NOTICE: running a Tor exit node is legal in most places, but please check your local rules. For legal resources, refer to https://community.torproject.org/relay/community-resources/

Credits:

Code by mentor.eth


Press any key to continue...

EOF

## ###############
## 1️⃣ Ask for user data
## ###############

# Check for old data
if test -f $DOCKER_COMPOSE_PATH/torrc1; then

  NODE_NICKNAME=$( grep -Po "(?<=Nickname )(.*)" $DOCKER_COMPOSE_PATH/torrc1 2> /dev/null )
  DAEMON_AMOUNT=$( grep -Po "(?<=DAEMON_AMOUNT=)(.*)" "$ONIONDAO_PATH/.oniondaorc" 2> /dev/null )
  NODE_BANDWIDTH=$( grep -Po "(?<=AccountingMax )(.*)(?= TB)" $DOCKER_COMPOSE_PATH/torrc1 2> /dev/null )
  OPERATOR_EMAIL=$( grep -Po "(?<=ContactInfo )(.*)" $DOCKER_COMPOSE_PATH/torrc1 2> /dev/null )
  OPERATOR_WALLET=$( grep -Po "(?<= address: )(.*)(?= -->)" $ONIONDAO_PATH/fixtures/index.html 2> /dev/null )
  OPERATOR_TWITTER=$( grep -Po "(?<=OPERATOR_TWITTER=)(.*)" "$ONIONDAO_PATH/.oniondaorc" 2> /dev/null )
  REDUCED_EXIT_POLICY=$( grep -Po "(?<=REDUCED_EXIT_POLICY=)(.*)" "$ONIONDAO_PATH/.oniondaorc" 2> /dev/null )

  echo -e "\n\n----------------------------------------"
  echo "You have existing configurations:"
  echo -e "----------------------------------------\n\n"

  echo "POAP wallet: $OPERATOR_WALLET"
  echo "Node nickname: $NODE_NICKNAME"
  echo "Operator email: $OPERATOR_EMAIL"
  echo "Operator twitter: $OPERATOR_TWITTER"
  echo "Monthly bandwidth limit: $NODE_BANDWIDTH TB"
  echo "Node amount: $NODE_AMOUNT"
  echo -e "Reduced exit policy: $REDUCED_EXIT_POLICY\n"

  read -p "Keep existing configurations? [Y/n] (default Y): " KEEP_OLD_CONFIGS
  KEEP_OLD_CONFIGS=${KEEP_OLD_CONFIGS:-"Y"}

fi

# Get new data if needed
if [[ "$KEEP_OLD_CONFIGS" == "Y" ]]; then
  echo  "Continuing with existing configuration settings"
  REDUCED_EXIT_POLICY=${REDUCED_EXIT_POLICY:-"Y"}
else

  echo -e "\n\n----------------------------------------"
  echo "Tor setup needs some information"
  echo -e "----------------------------------------\n\n"

  read -p "How many TB is this node allowed to use per month? (default 1, use 0 for unlimited): " NODE_BANDWIDTH
  NODE_BANDWIDTH=${NODE_BANDWIDTH:-"1"}

  echo -e "\nAre you on an (expensive) fully unmetered 1-10 Gbps connection?"
  echo "If so, you can run multiple daemons (up to 4 per ip address)."
  read -p "How many daemons do you want to run? (default 1): " DAEMON_AMOUNT
  DAEMON_AMOUNT=${DAEMON_AMOUNT:-"1"}

  echo -e "\nThere are 2 available exit policies in this script: ReducedExitPolicy and WebOnly."
  echo "ReducedExitPolicy: blocks most abuse ports (like Torrents, Email, etc)"
  echo -e "WebOnly: allows for only http(s) traffic, which is only partially useful to the Network\n"
  read -p "Do you want to ReducedExitPolicy? [Y/n] (default Y): " REDUCED_EXIT_POLICY
  REDUCED_EXIT_POLICY=${REDUCED_EXIT_POLICY:-"Y"}

  echo -e "\n\n----------------------------------------"
  echo "OnionDAO needs some information"
  echo -e "----------------------------------------\n\n"

  echo "⚠️ Note: Tor needs a valid email address so you can be contacted if there is an issue."
  echo -e "This address is public, you may want to use a dedicated email account for this, or if you use gmail use the + operator like so: yourname+tor@gmail.com. Read more about task-specific addresses here: https://support.google.com/a/users/answer/9308648?hl=en\n"
  read -p "Your email (requirement for a Tor node): " OPERATOR_EMAIL

  echo -e "\nYour node nickname is visible on the leaderboard at https://tor-relay.co/"
  read -p "Node nickname (requirement for a Tor node, only letters and numbers): " NODE_NICKNAME

  echo -e "\nYour Twitter handle is OPTIONAL and purely so you can be tweeted at if needed"
  read -p "Your twitter handle (optional): " OPERATOR_TWITTER

  # force node nickname to be only alphanumeric
  NODE_NICKNAME=$( echo $NODE_NICKNAME | tr -cd '[:alnum:]' )

  read -p "Your wallet address or ENS (to receive POAP): " OPERATOR_WALLET

  echo  -e "\n\n----------------------------------------"
  echo  "Check your information"
  echo  "----------------------------------------"
  echo  "POAP wallet: $OPERATOR_WALLET"
  echo  "Node nickname: $NODE_NICKNAME"
  echo  "Operator email: $OPERATOR_EMAIL"
  echo  "Operator twitter: $OPERATOR_TWITTER"
  echo  -e "Monthly bandwidth limit: $NODE_BANDWIDTH TB\n"
  echo "Press any key to continue or ctrl+c to exit..."
  read

fi

# Save data that is not in different places
echo "OPERATOR_TWITTER=$OPERATOR_TWITTER" > $ONIONDAO_PATH/.oniondaorc
echo "REDUCED_EXIT_POLICY=$REDUCED_EXIT_POLICY" >> $ONIONDAO_PATH/.oniondaorc
echo "DAEMON_AMOUNT=$DAEMON_AMOUNT" >> $ONIONDAO_PATH/.oniondaorc

## ###############
## 2️⃣ Install Tor
## ###############

# Install Docker, see https://docs.docker.com/engine/install/ubuntu/
echo -e "\nInstalling/updating docker..."
sudo apt -y remove docker docker-engine docker.io containerd runc &> /dev/null
sudo apt update &> /dev/null
sudo apt -y install \
    ca-certificates \
    curl \
    gnupg &> /dev/null
sudo mkdir -m 0755 -p /etc/apt/keyrings &> /dev/null
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update &> /dev/null
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &> /dev/null

# Get ipv4 of this server
REMOTE_IP=$( curl ipv4.icanhazip.com 2> /dev/null )
if [ ${#REMOTE_IP} -lt 7 ]; then
  echo "Remote ip: icanhaz unavailable, using canhaz"
  REMOTE_IP=$( curl ipv4.canhazip.com 2> /dev/null )
elif [ ${#REMOTE_IP} -lt 7 ]; then
  echo "Remote ip: canhaz unavailable, using ipify"
  REMOTE_IP=$( curl api.ipify.org 2> /dev/null )
elif [ ${#REMOTE_IP} -lt 7 ]; then
  echo "Remote ip: ipify unavailable, using seeip"
  REMOTE_IP=$( curl https://ip4.seeip.org 2> /dev/null )
fi

# Checking for ipv6
echo "Testing IPV6..."
ping6 -c2 2001:858:2:2:aabb:0:563b:1526 && ping6 -c2 2620:13:4000:6000::1000:118 && ping6 -c2 2001:67c:289c::9 && ping6 -c2 2001:678:558:1000::244 && ping6 -c2 2607:8500:154::3 && ping6 -c2 2001:638:a000:4140::ffff:189 && IPV6_GOOD=true
if [ -z "$IPV6_GOOD" ]; then
  echo "No ipv6 support, ignoring ipv6"
else
  IPV6_ADDRESS=$(ip -6 addr | grep inet6 | grep "scope global" | awk '{print $2}' | cut -d'/' -f1)
  if [ -z "$IPV6_ADDRESS" ];then
      echo "Could not automatically find your IPv6 address"
      echo "If you know your global (!) IPv6 address you can enter it now"
      echo "Please make sure that you enter it correctly and do not enter any other characters"
      echo "If you want to skip manual IPv6 setup leave the line blank and just press ENTER"
      read -p "IPv6 address: " IPV6_ADDRESS
    fi

fi

## ###############
## 3️⃣ Create Tor container spec for every DAEMON_AMOUNT
## ###############
rm -rf $DOCKER_COMPOSE_PATH/*
mkdir -p $DOCKER_COMPOSE_PATH
echo -e "
---
version: \"3\"
services:
  exit-notice:
    image: nginx
    container_name: exit_notice_webserver
    volumes:
      - $ONIONDAO_PATH/fixtures/:/usr/share/nginx/html:ro
    ports:
      - "80:80"
    environment:
      - NGINX_PORT=80
" > "$DOCKER_COMPOSE_PATH/docker-compose.yml" 

# Add docker-compose declarations for each node
for ((i=1;i<=$DAEMON_AMOUNT;++i)); do

  echo "Making daemon $i"

  # Make tor data folder to mount
  data_folder_path="$DOCKER_COMPOSE_PATH/tor-data-$i"
  torrc_file_path="$DOCKER_COMPOSE_PATH/torrc$i"
  mkdir -p $data_folder_path

  # Add docker-compose declarations
  echo -e "
  tor_daemon_$i:
    image: ilshidur/tor-relay
    container_name: tor_daemon_$i
    init: true
    restart: unless-stopped
    ports:
      - \"900$i:900$i\"
    environment:
      TOR_NICKNAME: $NODE_NICKNAME
      CONTACT_EMAIL: $OPERATOR_EMAIL
      PUID=$(id -u)
      PGID=$(id -g)
      TZ=Europe/London
    volumes:
      - $data_folder_path:/data
      - $torrc_file_path:/etc/tor/torrc:ro
  " >> "$DOCKER_COMPOSE_PATH/docker-compose.yml"

  # Shared config
  cat $ONIONDAO_PATH/fixtures/shared.torrc > $torrc_file_path
  if [[ "$REDUCED_EXIT_POLICY" == "Y" ]]; then
    cat $ONIONDAO_PATH/fixtures/rep-policy.torrc >> $torrc_file_path
  else
    cat $ONIONDAO_PATH/fixtures/web-only.torrc >> $torrc_file_path
  fi

  # Use accounting?
  if [ "$NODE_BANDWIDTH" -eq "0" ]; then
    echo "No bandwidth limit set in $torrc_file_path"
  else
    echo -e "
    # Bandwidth accounting
    AccountingStart month 1 00:00
    AccountingMax $NODE_BANDWIDTH TB
    " >> $torrc_file_path
  fi

  # Unique config
  echo -e "
    # Variables
    Nickname $NODE_NICKNAME
    ContactInfo $OPERATOR_EMAIL
    ORPort 900$i
    ControlPort 905$i
  " >> $torrc_file_path

  if [ -z "$IPV6_ADDRESS" ];then
    echo "Skipping ipv6 for $torrc_file_path"
  else
    echo -e "
      # Ipv6
      IPv6Exit 1
      ORPort [$IPV6_ADDRESS]:900$i
    " >> $torrc_file_path
  fi

  # Trim whitespace
  sed -ir 's/\s+//g' $torrc_file_path

done

# Start all containers
cd $DOCKER_COMPOSE_PATH
docker compose up -d

# wait for tor to come online 
# keep the user entertained with status updates
echo "Waiting for Tor to come online, just a moment..."
echo "This can take a few minutes. DO NOT EXIT THIS SCRIPT."

# Write exit file
cp $ONIONDAO_PATH/fixtures/tor-exit-notice.template.html $ONIONDAO_PATH/fixtures/index.html
sed -i "s/FIXME_YOUR_EMAIL_ADDRESS/$OPERATOR_EMAIL/g" $ONIONDAO_PATH/fixtures/index.html
sed -i "s/FIXME_DNS_NAME/$REMOTE_IP/g" $ONIONDAO_PATH/fixtures/index.html
echo "<!-- OnionDAO address: $OPERATOR_WALLET -->" >> $ONIONDAO_PATH/fixtures/index.html

PROGRESS="#"
until curl "http://127.0.0.1" &> /dev/null; do
  echo -en "\e[K$PROGRESS"
  RANDOM_BETWEEN_1_AND_5=$(( ( RANDOM % 5 )  + 1 ))
  PROGRESS="$PROGRESS#"
  sleep "$RANDOM_BETWEEN_1_AND_5"
done
until nc -z 127.0.0.1 9001 &> /dev/null; do
  echo -en "\e[K$PROGRESS"
  RANDOM_BETWEEN_1_AND_5=$(( ( RANDOM % 5 )  + 1 ))
  PROGRESS="$PROGRESS#"
  sleep "$RANDOM_BETWEEN_1_AND_5"
done

## ###############
## 4️⃣ Register with OnionDao
## ###############

cat << "EOF"

===========================================

__   __ _  __  __   __ _    ____   __    __   ____ 
 /  \ (  ( \(  )/  \ (  ( \  (  _ \ /  \  / _\ (  _ \
(  O )/    / )((  O )/    /   ) __/(  O )/    \ ) __/
 \__/ \_)__)(__)\__/ \_)__)  (__)   \__/ \_/\_/(__)


===========================================

If you see no errors above, setup is complete. If you haven't already, it is highly recommended to:

- Enable SSH key authentication
  > Beginner resource 1: https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-20-04
  > Beginner resource 2: https://docs.rocketpool.net/guides/node/securing-your-node.html#essential-secure-your-ssh-access


===========================================

EOF


echo "------------------------------------------------------"
echo "Registering node with OnionDAO..."
echo -e "------------------------------------------------------\n"

## ###############
## Data sanitation
## ###############

# Check for the (current) edge case that this is a ipv6-only server, assumption: if we could not find an ipv4, you are an ipv6
if [ ${#REMOTE_IP} -lt 7 ]; then
  echo "Could not find an ipv4 address for your server, using ipv6"
  REMOTE_IP="$IPV6_ADDRESS"
fi

# Formulate post data format
post_data="{"
post_data="$post_data\"ip\": \"$REMOTE_IP\""
post_data="$post_data,\"email\": \"$OPERATOR_EMAIL\""
post_data="$post_data,\"bandwidth\": \"$NODE_BANDWIDTH\""
post_data="$post_data,\"reduced_exit_policy\": \"$REDUCED_EXIT_POLICY\""
post_data="$post_data,\"node_nickname\": \"$NODE_NICKNAME\""
post_data="$post_data,\"wallet\": \"$OPERATOR_WALLET\""

if [ ${#OPERATOR_TWITTER} -gt 3 ]; then
  post_data="$post_data,\"twitter\": \"$OPERATOR_TWITTER\""
fi

post_data="$post_data}"

# Register node with Onion DAO oracle
curl -X POST https://oniondao.web.app/api/tor_nodes \
  -H 'Content-Type: application/json' \
  -d "$post_data"

echo -e "\n\n------------------------------------------------------"
echo "Want to stay up to date on OnionDAO developments?"
echo -e "------------------------------------------------------\n"
echo -e "👉 Join us in the Rocketeer discord in the #onion-dao channel: https://discord.gg/rocketeers\n"

# 🔥 add the current user to the tor user group so that we can run Nyx without sudo
# this is a known Nyx annoyance, see https://github.com/torproject/nyx/issues/24
sudo adduser $USER debian-tor
exec sudo su -l $USER # make sure relogin is not needed, see https://superuser.com/a/609141