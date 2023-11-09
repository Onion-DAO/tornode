# 🧅 OnionDAO Tornode

This is an initiative by the [OnionDAO](https://oniondao.web.app/).

To qualify for your POAP you need to:

1. Set up an exit node (see setup script below)
1. Keep your node running for at least one month
1. Claim your POAP at [poap.delivery](https://poap.delivery/)

Direct link to the POAP for: [April](https://poap.delivery/oniondao-tor-node-runner-april-2022), [May](https://poap.delivery/oniondao-tor-node-runner-may-2022), [June](https://poap.delivery/oniondao-tor-node-runner-june-2022), [July](https://poap.delivery/oniondao-tor-node-runner-july-2022) 2022

---


## Setup TL;DR

Are you in a rush?

1. Buy a VPS with 1.5GB ram ([crowdsourced list of suitable providers here](https://docs.google.com/spreadsheets/d/1ztkonpfs0u3NP1HA-V6rhE6eK77W6y0Q8gG_yv9tI3s))
2. Run `curl https://raw.githubusercontent.com/Onion-DAO/tornode/main/setup.sh --output oniondao.setup.sh && sudo bash oniondao.setup.sh $HOME && rm oniondao.setup.sh`
3. Follow on-screen instructions

---

# Text instructions

You should run your Tor exit node in a data center, probably as a VPS. The requires specs are:

1. Any modern CPU
1. 1.5 GB RAM
1. 256MB disk space available for Tor

For details see [the official documentation]( https://community.torproject.org/relay/relays-requirements/ ).

## Setup steps

In order to qualify for an Onion POAP, you need to run a Tor exit node. Ideally, you do so at a datacenter. We're going to assume you are using a VPS (virtual private server) with Ubuntu `20.04 LTS`.

### Step 1: purchase a VPS

Not all VPS providers like it if you run a Tor exit node.

- OnionDAO keeps a [crowdsourced list of suitable providers here](https://docs.google.com/spreadsheets/d/1ztkonpfs0u3NP1HA-V6rhE6eK77W6y0Q8gG_yv9tI3s)
- The Tor community keeps a [ list of exit node friendly providers here ]( https://community.torproject.org/relay/community-resources/good-bad-isps/ )
- A crypto community member hosts a list of [ those accepting Bitcoin here ]( https://torbitcoinvps.github.io/ )

Most VPS providers have different VPS options. Choose one that has at least 1.5GB RAM. When asked about an operating system, choose Ubuntu `20.04 LTS`.

Your provider should send you a username, password and ip address. `Ssh` into your server now.

### Step 2: run the install script

Clone this repo and run the setup script:

```
git clone https://github.com/Onion-DAO/tornode.git
cd tornode
sudo bash setup.sh
```

### Step 3: keep it running for a month

After a month, the POAPs will de distributed through poap.delivery.

---

# Video instructions

Do you prefer a video walkthrough? You can view a recording of our setup livestream [here in the Rocketeer Discord]( https://discord.com/channels/899629740766412890/959100274587344966/959193725458858064 ).
