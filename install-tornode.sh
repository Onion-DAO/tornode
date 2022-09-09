#!/bin/bash

# Global config
BIN_FOLDER=/usr/local/sbin
ONIONDAO_PATH="$HOME/.oniondao/"

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

Setup script based on https://tor-relay.co/
Code by mentor.eth


Press any key to continue...

EOF

## ###############
## The below script is based
## on https://tor-relay.co/
## edits marked with 🔥
## ###############

read

# 🔥 Minor annoyance fix on some VPS systems where the hostname is not in the hosts file
if sudo grep -q "$(hostname)" /etc/hosts; then
  echo "Hostname is in /etc/hosts"
else
  sudo echo "127.0.0.1 $( hostname )" >> /etc/hosts
fi 


RELEASE='focal'
IS_EXIT=true
IS_BRIDGE=false
INSTALL_NYX=true
CHECK_IPV6=true
ENABLE_AUTO_UPDATE=true
OBFS4PORT_LT_1024=true

C_RED="\e[31m"
C_GREEN="\e[32m"
C_CYAN="\e[36m"
C_DEFAULT="\e[39m"

function echoInfo() {
  echo -e "${C_CYAN}$1${C_DEFAULT}"
}

function echoError() {
  echo -e "${C_RED}$1${C_DEFAULT}"
}

function echoSuccess() {
  echo -e "${C_GREEN}$1${C_DEFAULT}"
}

function handleError() {
  echoError "-> ERROR"
  sudo /etc/init.d/tor stop
  echoError "An error occured on the last setup step."
  echoError "If you think there is a problem with this script please share information about the error and you system configuration for debugging: tor@flxn.de"
}

## ###############
## Check environment
## ###############
# 🔥 check for ubuntu 20.04 LTS focal
if cat /etc/os-release | grep -q UBUNTU_CODENAME=focal; then
  echoInfo "✅ You are on Ubuntu 20.04 codename Focal"
else
  echoError "⚠️ You are not on Ubuntu 20.04, this script might not work for you. Please reinstall your server as Ubuntu 20.04 LTS."
  echoError "Press any key to continue, knowing this might fail..."
  read
fi

## ###############
## Get needed data
## ###############

## ###############
## CHeck for old data
## ###############
if test -f /etc/tor/torrc; then
  NODE_NICKNAME=$( grep -Po "(?<=Nickname )(.*)" /etc/tor/torrc 2> /dev/null )
  NODE_BANDWIDTH=$( grep -Po "(?<=AccountingMax )(.*)(?= TB)" /etc/tor/torrc 2> /dev/null )
  OPERATOR_EMAIL=$( grep -Po "(?<=ContactInfo )(.*)" /etc/tor/torrc 2> /dev/null )
  OPERATOR_WALLET=$( grep -Po "(?<= address: )(.*)(?= -->)" /etc/tor/tor-exit-notice.html 2> /dev/null )
  OPERATOR_TWITTER=$( grep -Po "(?<=OPERATOR_TWITTER=)(.*)" "$ONIONDAO_PATH/.oniondaorc" 2> /dev/null )
  REDUCED_EXIT_POLICY=$( grep -Po "(?<=REDUCED_EXIT_POLICY=)(.*)" "$ONIONDAO_PATH/.oniondaorc" 2> /dev/null )

  echoInfo "\n\n----------------------------------------"
  echoInfo "You have existing configurations:"
  echoInfo "----------------------------------------\n\n"

  echoInfo "POAP wallet: $OPERATOR_WALLET"
  echoInfo "Node nickname: $NODE_NICKNAME"
  echoInfo "Operator email: $OPERATOR_EMAIL"
  echoInfo "Operator twitter: $OPERATOR_TWITTER"
  echoInfo "Monthly bandwidth limit: $NODE_BANDWIDTH TB"
  echoInfo "Reduced exit policy: $REDUCED_EXIT_POLICY\n"

  read -p "Keep existing configurations? [Y/n] (default Y): " KEEP_OLD_CONFIGS
  KEEP_OLD_CONFIGS=${KEEP_OLD_CONFIGS:-"Y"}

fi

## ###############
## Get new data
## ###############
if [[ "$KEEP_OLD_CONFIGS" == "Y" ]]; then
  echoSuccess "Continuing with existing configuration settings"
  REDUCED_EXIT_POLICY=${REDUCED_EXIT_POLICY:-"Y"}
else

  echoInfo "\n\n----------------------------------------"
  echoInfo "Tor setup needs some information"
  echoInfo "----------------------------------------\n\n"

  read -p "How many TB is this node allowed to use per month? (default 1 TB): " NODE_BANDWIDTH
  NODE_BANDWIDTH=${NODE_BANDWIDTH:-"1"}

  echo -e "\nThere are 2 available exit policies in this script: ReducedExitPolicy and WebOnly."
  echo "ReducedExitPolicy: blocks most abuse ports (like Torrents, Email, etc)"
  echo -e "WebOnly: allows for only http(s) traffic, which is only partially useful to the Network\n"
  read -p "Do you want to ReducedExitPolicy? [Y/n] (default Y): " REDUCED_EXIT_POLICY
  REDUCED_EXIT_POLICY=${REDUCED_EXIT_POLICY:-"Y"}

  echoInfo "\n\n----------------------------------------"
  echoInfo "OnionDAO needs some information"
  echoInfo "----------------------------------------\n\n"

  echoError "Note: Tor needs a valid email address so you can be contacted if there is an issue."
  echoInfo "This address is public, you may want to use a dedicated email account for this, or if you use gmail use the + operator like so: yourname+tor@gmail.com. Read more about task-specific addresses here: https://support.google.com/a/users/answer/9308648?hl=en\n"
  read -p "Your email (requirement for a Tor node): " OPERATOR_EMAIL

  echoInfo "\nYour node nickname is visible on the leaderboard at https://tor-relay.co/"
  read -p "Node nickname (requirement for a Tor node, only letters and numbers): " NODE_NICKNAME

  echoInfo "\nYour Twitter handle is OPTIONAL and purely so you can be tweeted at if needed"
  read -p "Your twitter handle (optional): " OPERATOR_TWITTER

  # force node nickname to be only alphanumeric
  NODE_NICKNAME=$( echo $NODE_NICKNAME | tr -cd '[:alnum:]' )

  read -p "Your wallet address or ENS (to receive POAP): " OPERATOR_WALLET

  echoSuccess "\n\n----------------------------------------"
  echoSuccess "Check your information"
  echoSuccess "----------------------------------------"
  echoSuccess "POAP wallet: $OPERATOR_WALLET"
  echoSuccess "Node nickname: $NODE_NICKNAME"
  echoSuccess "Operator email: $OPERATOR_EMAIL"
  echoSuccess "Operator twitter: $OPERATOR_TWITTER"
  echoSuccess "Monthly bandwidth limit: $NODE_BANDWIDTH TB\n"
  echoInfo "Press any key to continue or ctrl+c to exit..."
  read

fi


# 🔥 removed logo to prevent confusion, are you from tor-relay and reading this? I'm happy to add attribution in any way you like, contact me on Twitter :)
# echo -e $C_CYAN #cyan
# cat << "EOF"

#  _____            ___     _
# |_   _|__ _ _ ___| _ \___| |__ _ _  _   __ ___
#   | |/ _ \ '_|___|   / -_) / _` | || |_/ _/ _ \
#   |_|\___/_|     |_|_\___|_\__,_|\_, (_)__\___/
#                                  |__/

# EOF

## ###############
## Get remote IP
## ###############

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

echo -e $C_DEFAULT #default
echo "              [Relay Setup]"
echo "This script might ask for your sudo password."
echo "----------------------------------------------------------------------"

echoInfo "Updating package list..."
sudo apt-get -y update > /dev/null && echoSuccess "-> OK" || handleError

echoInfo "Installing necessary packages..."
sudo apt-get -y install apt-transport-https psmisc dirmngr ntpdate curl > /dev/null && echoSuccess "-> OK" || handleError

# 🔥 install fails with old certificate package
echoInfo "Upgrading essential packages"
sudo apt-get -y install ca-certificates > /dev/null && echoSuccess "-> OK" || handleError

echoInfo "Updating NTP..."
# 🔥 NTP already runs on 20.04 causing issues, removing error logging
# sudo ntpdate pool.ntp.org > /dev/null && echoSuccess "-> OK" || handleError
sudo ntpdate pool.ntp.org > /dev/null && echoSuccess "-> OK"

echoInfo "Adding Torproject apt repository..."
sudo touch /etc/apt/sources.list.d/tor.list && echoSuccess "-> touch OK" || handleError
ARCH=`dpkg --print-architecture`
echo "deb [arch=$ARCH] https://deb.torproject.org/torproject.org $RELEASE main" | sudo tee /etc/apt/sources.list.d/tor.list > /dev/null && echoSuccess "-> tee1 OK" || handleError
echo "deb-src [arch=$ARCH] https://deb.torproject.org/torproject.org $RELEASE main" | sudo tee --append /etc/apt/sources.list.d/tor.list > /dev/null && echoSuccess "-> tee2 OK" || handleError

echoInfo "Adding Torproject GPG key..."
curl https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo apt-key add - && echoSuccess "-> OK" || handleError

echoInfo "Updating package list..."
sudo apt-get -y update > /dev/null && echoSuccess "-> OK" || handleError

if $INSTALL_NYX
then
  echoInfo "Installing NYX..."
  NYX_INSTALL_OK=false
  sudo apt-get -y install python3-distutils &> /dev/null
  sudo apt-get -y install nyx > /dev/null && NYX_INSTALL_OK=true && echoSuccess "-> OK" || echoError "-> Error installing NYX via apt"

  if [ ! NYX_INSTALL_OK ]
  then
    echoInfo "Trying again via pip..."
    sudo apt-get -y install python3-pip > /dev/null
    sudo pip3 install nyx > /dev/null && echoSuccess "-> OK" || echoError "-> pip install failed too.\nPlease check the nyx homepage: https://nyx.torproject.org/#download"
  fi
fi

echoInfo "Installing Tor..."
sudo apt-get -y install tor deb.torproject.org-keyring > /dev/null && echoSuccess "-> install OK" || handleError
sudo chown -R debian-tor:debian-tor /var/log/tor && echoSuccess "-> chown OK" || handleError

if $IS_BRIDGE
then
  echoInfo "Installing obfs4proxy..."
  sudo apt-get -y install obfs4proxy > /dev/null && echoSuccess "-> OK" || handleError

  if $OBFS4PORT_LT_1024
  then
    echoInfo "Setting net_bind_service capability for non-root user"
    sudo setcap cap_net_bind_service=+ep /usr/bin/obfs4proxy && echoSuccess "-> OK" || handleError
  fi

  sudo sed -i -e 's/NoNewPrivileges=yes/NoNewPrivileges=no/' /lib/systemd/system/tor@default.service && echoSuccess "-> sed OK" || handleError
  systemctl daemon-reload && echoSuccess "-> daemon-reload OK" || handleError
fi

echoInfo "Setting Tor config..."

if [[ "$REDUCED_EXIT_POLICY" == "Y" ]]; then

cat << EOF | sudo tee /etc/tor/torrc > /dev/null && echoSuccess "-> OK" || handleError
  SocksPort 0
  RunAsDaemon 1
  ORPort 9001
  ORPort [INSERT_IPV6_ADDRESS]:9001
  Nickname $NODE_NICKNAME
  ContactInfo $OPERATOR_EMAIL
  Log notice file /var/log/tor/notices.log
  DirPort 80
  DirPortFrontPage /etc/tor/tor-exit-notice.html
  ExitPolicy accept *:20-23     # FTP, SSH, telnet
  ExitPolicy accept *:43        # WHOIS
  ExitPolicy accept *:53        # DNS
  ExitPolicy accept *:79-81     # finger, HTTP
  ExitPolicy accept *:88        # kerberos
  ExitPolicy accept *:110       # POP3
  ExitPolicy accept *:143       # IMAP
  ExitPolicy accept *:194       # IRC
  ExitPolicy accept *:220       # IMAP3
  ExitPolicy accept *:389       # LDAP
  ExitPolicy accept *:443       # HTTPS
  ExitPolicy accept *:464       # kpasswd
  ExitPolicy accept *:465       # URD for SSM (more often: an alternative SUBMISSION port, see 587)
  ExitPolicy accept *:531       # IRC/AIM
  ExitPolicy accept *:543-544   # Kerberos
  ExitPolicy accept *:554       # RTSP
  ExitPolicy accept *:563       # NNTP over SSL
  ExitPolicy accept *:587       # SUBMISSION (authenticated clients [MUA's like Thunderbird] send mail over STARTTLS SMTP here)
  ExitPolicy accept *:636       # LDAP over SSL
  ExitPolicy accept *:706       # SILC
  ExitPolicy accept *:749       # kerberos
  ExitPolicy accept *:873       # rsync
  ExitPolicy accept *:902-904   # VMware
  ExitPolicy accept *:981       # Remote HTTPS management for firewall
  ExitPolicy accept *:989-990   # FTP over SSL
  ExitPolicy accept *:991       # Netnews Administration System
  ExitPolicy accept *:992       # TELNETS
  ExitPolicy accept *:993       # IMAP over SSL
  ExitPolicy accept *:994       # IRCS
  ExitPolicy accept *:995       # POP3 over SSL
  ExitPolicy accept *:1194      # OpenVPN
  ExitPolicy accept *:1220      # QT Server Admin
  ExitPolicy accept *:1293      # PKT-KRB-IPSec
  ExitPolicy accept *:1500      # VLSI License Manager
  ExitPolicy accept *:1533      # Sametime
  ExitPolicy accept *:1677      # GroupWise
  ExitPolicy accept *:1723      # PPTP
  ExitPolicy accept *:1755      # RTSP
  ExitPolicy accept *:1863      # MSNP
  ExitPolicy accept *:2082      # Infowave Mobility Server
  ExitPolicy accept *:2083      # Secure Radius Service (radsec)
  ExitPolicy accept *:2086-2087 # GNUnet, ELI
  ExitPolicy accept *:2095-2096 # NBX
  ExitPolicy accept *:2102-2104 # Zephyr
  ExitPolicy accept *:3128      # SQUID
  ExitPolicy accept *:3389      # MS WBT
  ExitPolicy accept *:3690      # SVN
  ExitPolicy accept *:4321      # RWHOIS
  ExitPolicy accept *:4643      # Virtuozzo
  ExitPolicy accept *:5050      # MMCC
  ExitPolicy accept *:5190      # ICQ
  ExitPolicy accept *:5222-5223 # XMPP, XMPP over SSL
  ExitPolicy accept *:5228      # Android Market
  ExitPolicy accept *:5900      # VNC
  ExitPolicy accept *:6660-6669 # IRC
  ExitPolicy accept *:6679      # IRC SSL
  ExitPolicy accept *:6697      # IRC SSL
  ExitPolicy accept *:8000      # iRDMI
  ExitPolicy accept *:8008      # HTTP alternate
  ExitPolicy accept *:8074      # Gadu-Gadu
  ExitPolicy accept *:8080      # HTTP Proxies
  ExitPolicy accept *:8082      # HTTPS Electrum Bitcoin port
  ExitPolicy accept *:8087-8088 # Simplify Media SPP Protocol, Radan HTTP
  ExitPolicy accept *:8332-8333 # Bitcoin
  ExitPolicy accept *:8443      # PCsync HTTPS
  ExitPolicy accept *:8888      # HTTP Proxies, NewsEDGE
  ExitPolicy accept *:9418      # git
  ExitPolicy accept *:9999      # distinct
  ExitPolicy accept *:10000     # Network Data Management Protocol
  ExitPolicy accept *:11371     # OpenPGP hkp (http keyserver protocol)
  ExitPolicy accept *:19294     # Google Voice TCP
  ExitPolicy accept *:19638     # Ensim control panel
  ExitPolicy accept *:50002     # Electrum Bitcoin SSL
  ExitPolicy accept *:64738     # Mumble
  ExitPolicy reject *:*
  ExitRelay 1
  IPv6Exit 1
  AccountingStart month 1 00:00
  AccountingMax $NODE_BANDWIDTH TB
  DisableDebuggerAttachment 0
  ControlPort 9051
  CookieAuthentication 1

EOF
else

cat << EOF | sudo tee /etc/tor/torrc > /dev/null && echoSuccess "-> OK" || handleError
  SocksPort 0
  RunAsDaemon 1
  ORPort 9001
  ORPort [INSERT_IPV6_ADDRESS]:9001
  Nickname $NODE_NICKNAME
  ContactInfo $OPERATOR_EMAIL
  Log notice file /var/log/tor/notices.log
  DirPort 80
  DirPortFrontPage /etc/tor/tor-exit-notice.html
  ExitPolicy accept *:53        # DNS
  ExitPolicy accept *:80     # finger, HTTP
  ExitPolicy accept *:443       # HTTPS
  ExitPolicy reject *:*
  ExitRelay 1
  IPv6Exit 1
  AccountingStart month 1 00:00
  AccountingMax $NODE_BANDWIDTH TB
  DisableDebuggerAttachment 0
  ControlPort 9051
  CookieAuthentication 1

EOF

fi
if $IS_EXIT
then
  echoInfo "Downloading Exit Notice to /etc/tor/tor-exit-notice.html..."

  # 🔥 commented out notices
  # echo -e "\e[1mPlease edit this file and replace FIXME_YOUR_EMAIL_ADDRESS with your e-mail address!"
  echo -e "\e[1mAlso note that this is the US version. If you are not in the US please edit the file and remove the US-Only sections!\e[0m"
  sudo wget -q -O /etc/tor/tor-exit-notice.html "https://raw.githubusercontent.com/flxn/tor-relay-configurator/master/misc/tor-exit-notice.html" && echoSuccess "-> OK" || handleError

  # 🔥 added auto search-replace of email
  sed -i "s/FIXME_YOUR_EMAIL_ADDRESS/$OPERATOR_EMAIL/g" /etc/tor/tor-exit-notice.html

  # 🔥 address name in message
  sed -i "s/FIXME_DNS_NAME/$REMOTE_IP/g" /etc/tor/tor-exit-notice.html

  # 🔥 added a comment to the tor notice page with the POAP address so I can scrape it for distribution
  echo "<!-- OnionDAO address: $OPERATOR_WALLET -->" >> /etc/tor/tor-exit-notice.html

fi

function disableIPV6() {
  sudo sed -i -e '/INSERT_IPV6_ADDRESS/d' /etc/tor/torrc
  sudo sed -i -e 's/IPv6Exit 1/IPv6Exit 0/' /etc/tor/torrc
  sudo sed -i -e '/\[..\]/d' /etc/tor/torrc
  echoError "IPv6 support has been disabled!"
  echo "If you want to enable it manually find out your IPv6 address and add this line to your /etc/tor/torrc"
  echo "ORPort [YOUR_IPV6_ADDRESS]:YOUR_ORPORT (example: \"ORPort [2001:123:4567:89ab::1]:9001\")"
  echo "or for a bridge: ServerListenAddr obfs4 [..]:YOUR_OBFS4PORT"
  echo "Then run \"sudo /etc/init.d/tor restart\" to restart Tor"
}

if $CHECK_IPV6
then
  echoInfo "Testing IPV6..."
  IPV6_GOOD=false
  ping6 -c2 2001:858:2:2:aabb:0:563b:1526 && ping6 -c2 2620:13:4000:6000::1000:118 && ping6 -c2 2001:67c:289c::9 && ping6 -c2 2001:678:558:1000::244 && ping6 -c2 2607:8500:154::3 && ping6 -c2 2001:638:a000:4140::ffff:189 && IPV6_GOOD=true
  if [ ! IPV6_GOOD ]
  then
    sudo /etc/init.d/tor stop
    echoError "Could not reach Tor directory servers via IPV6"
    disableIPV6
  else
    echoSuccess "Seems like your IPV6 connection is working"

    IPV6_ADDRESS=$(ip -6 addr | grep inet6 | grep "scope global" | awk '{print $2}' | cut -d'/' -f1)
    if [ -z "$IPV6_ADDRESS" ]
    then
      echoError "Could not automatically find your IPv6 address"
      echo "If you know your global (!) IPv6 address you can enter it now"
      echo "Please make sure that you enter it correctly and do not enter any other characters"
      echo "If you want to skip manual IPv6 setup leave the line blank and just press ENTER"
      read -p "IPv6 address: " IPV6_ADDRESS

      if [ -z "$IPV6_ADDRESS" ]
      then
        disableIPV6
      else
        sudo sed -i "s/INSERT_IPV6_ADDRESS/$IPV6_ADDRESS/" /etc/tor/torrc
        echoSuccess "IPv6 Support enabled ($IPV6_ADDRESS)"
      fi
    else
      sudo sed -i "s/INSERT_IPV6_ADDRESS/$IPV6_ADDRESS/" /etc/tor/torrc
      echoSuccess "IPv6 Support enabled ($IPV6_ADDRESS)"
    fi
  fi
fi

if $ENABLE_AUTO_UPDATE
then
  echoInfo "Enabling unattended upgrades..."
  sudo apt-get install -y unattended-upgrades apt-listchanges > /dev/null && echoSuccess "-> install OK" || handleError
  DISTRO=$(lsb_release -is)
  sudo wget -q -O /etc/apt/apt.conf.d/50unattended-upgrades "https://raw.githubusercontent.com/flxn/tor-relay-configurator/master/misc/50unattended-upgrades.$DISTRO" && echoSuccess "-> wget OK" || handleError
  echoInfo "Don't install recommends..."
  sudo wget -q -O /etc/apt/apt.conf.d/40norecommends "https://raw.githubusercontent.com/flxn/tor-relay-configurator/master/misc/40norecommends" && echoSuccess "-> wget OK" || handleError
fi

sleep 10

echoInfo "Reloading Tor config..."
sudo /etc/init.d/tor restart

# 🔥 wait for tor to come online 
# keep the user entertained with status updates
echo "Waiting for Tor to come online, just a moment..."
echo "This can take a few minutes. DO NOT EXIT THIS SCRIPT."

PROGRESS="#"
until curl "http://127.0.0.1" &> /dev/null; do
  echo -en "\e[K$PROGRESS"
  RANDOM_BETWEEN_1_AND_5=$(( ( RANDOM % 5 )  + 1 ))
  PROGRESS="$PROGRESS#"
  sleep "$RANDOM_BETWEEN_1_AND_5"
done

echo ""
echoSuccess "=> Setup finished"
echo ""
# echo "Tor will now check if your ports are reachable. This may take up to 20 minutes."
# 🔥 Removed references to manually checking things
# echo "Check /var/log/tor/notices.log for an entry like:"
# echo "\"Self-testing indicates your ORPort is reachable from the outside. Excellent.\""
# echo ""

# sleep 5

# 🔥 Ignore false positive prone message
# if [ ! -f /var/log/tor/notices.log ]; then
#   echoError "Could not find Tor logfile."
#   echo "This could indicate an error. Check syslog for error messages from Tor:"
#   echo "  /var/log/syslog | grep -i tor"
#   echo "It could also be a false positive. Wait a bit and check the log file again."
#   echo "If you chose to install nyx you can check nyx to see if Tor is running."
# fi

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


echoInfo "------------------------------------------------------"
echoInfo "Registering node with OnionDAO..."
echoInfo "------------------------------------------------------\n"

## ###############
## Data sanitation
## ###############

# Save data that is not in different places
echo "OPERATOR_TWITTER=$OPERATOR_TWITTER" > $ONIONDAO_PATH/.oniondaorc
echo "REDUCED_EXIT_POLICY=$REDUCED_EXIT_POLICY" >> $ONIONDAO_PATH/.oniondaorc

# Check for the (current) edge case that this is a ipv6-only server, assumption: if we could not find an ipv4, you are an ipv6
if [ ${#REMOTE_IP} -lt 7 ]; then
  echoInfo "Could not find an ipv4 address for your server, using ipv6"
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

echoInfo "\n\n------------------------------------------------------"
echoInfo "Want to stay up to date on OnionDAO developments?"
echoInfo "------------------------------------------------------\n"
echoInfo "👉 Join us in the Rocketeer discord in the #onion-dao channel: https://discord.gg/rocketeers\n"

# 🔥 add the current user to the tor user group so that we can run Nyx without sudo
# this is a known Nyx annoyance, see https://github.com/torproject/nyx/issues/24
sudo adduser $USER debian-tor
exec sudo su -l $USER # make sure relogin is not needed, see https://superuser.com/a/609141
