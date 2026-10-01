# 🧅 OnionDAO Tornode

Turn a fresh server into a Tor exit relay and register it with the [OnionDAO](https://oniondao.web.app/) oracle, which rewards exit operators.

To qualify for your POAP:

1. Set up an exit node with the command below
1. Keep it running for at least a month
1. Claim your POAP at [poap.delivery](https://poap.delivery)

---

## Quick start

On a fresh server running **Ubuntu 26.04 / 24.04** or **Debian 13 / 12** (amd64 or arm64):

```bash
curl -fsSL https://raw.githubusercontent.com/Onion-DAO/tornode/main/setup.sh | sudo bash
```

Answer the prompts. Done in about 5 minutes.

**Server requirements:** 1.5 GB RAM, a public IPv4 address, ports 80 and 9001 reachable, and a provider that allows Tor exits ([OnionDAO's list](https://docs.google.com/spreadsheets/d/1ztkonpfs0u3NP1HA-V6rhE6eK77W6y0Q8gG_yv9tI3s), [Tor's list](https://community.torproject.org/relay/community-resources/good-bad-isps/), [Bitcoin-friendly hosts](https://torbitcoinvps.github.io/)). Details: [Tor relay requirements](https://community.torproject.org/relay/relays-requirements/).

### Unattended install

For cloud-init, Ansible and friends:

```bash
curl -fsSL https://raw.githubusercontent.com/Onion-DAO/tornode/main/setup.sh \
  | sudo ONIONDAO_EMAIL=you@example.com ONIONDAO_NICKNAME=myexit ONIONDAO_WALLET=you.eth bash -s -- --yes
```

| Variable | Default | |
| --- | --- | --- |
| `ONIONDAO_EMAIL` | required | Public contact for your relay |
| `ONIONDAO_NICKNAME` | required | 1-19 letters and digits |
| `ONIONDAO_WALLET` | required | `0x…` address or ENS name, receives POAPs and rewards |
| `ONIONDAO_BANDWIDTH_TB` | `1` | Monthly traffic cap in TB |
| `ONIONDAO_EXIT_POLICY` | `reduced` | `reduced` (Tor's ReducedExitPolicy) or `web` (DNS + http(s) only) |
| `ONIONDAO_TWITTER` | | Optional handle, without `@` |
| `ONIONDAO_AUTO_UPDATE` | `yes` | Daily OnionDAO updates |
| `ONIONDAO_UNBOUND` | `yes` | Local DNSSEC resolver for exit traffic |
| `ONIONDAO_TORRC_EXTRA` | | Extra torrc lines, saved to `/etc/tor/torrc.d/50-oniondao-extra.conf` |

---

## CLI

| Command | |
| --- | --- |
| `oniondao status` | Configuration, Tor and update health |
| `sudo oniondao install` | Set up or reconfigure the exit relay |
| `sudo oniondao update` | Pull the latest OnionDAO and re-apply your configuration |
| `sudo oniondao register` | Register an existing Tor exit relay (set up without OnionDAO) |
| `sudo oniondao autoupdate on\|off` | Toggle daily automatic updates |
| `sudo oniondao debug` | Diagnostics to share when asking for help |

Options for `install`, `update` and `register`: `--yes` (no prompts), `--no-register`, `--no-unbound`, `--no-auto-update`, `--force` (untested OS release).

Live relay monitor: `sudo nyx`

---

## What it sets up

- **Tor** from the [Tor Project's repository](https://support.torproject.org/little-t-tor/getting-started/installing/) (0.4.9+), key fingerprint verified
- **Exit relay**: `ReducedExitPolicy` (or web-only), IPv4 + IPv6, monthly bandwidth cap, [CIISS](https://nusenu.github.io/ContactInfo-Information-Sharing-Specification/) ContactInfo
- **Exit notice** on port 80, Tor's [official template](https://community.torproject.org/relay/setup/exit/) with your contact details. The OnionDAO oracle reads your wallet from it.
- **unbound** as local DNSSEC-validating resolver for exit traffic, as [Tor recommends](https://community.torproject.org/relay/setup/exit/)
- **Unattended upgrades** for Tor and distro security updates
- **Daily OnionDAO updates** via the `oniondao-update.timer` systemd timer

| Path | |
| --- | --- |
| `/opt/oniondao` | OnionDAO code (git checkout) |
| `/etc/oniondao/oniondao.conf` | Your settings |
| `/etc/oniondao/tor-exit-notice.html` | Optional: your own exit notice template, e.g. without the US-specific sections |
| `/etc/tor/torrc` | Generated, overwritten on update |
| `/etc/tor/torrc.d/*.conf` | Your own Tor options, kept on update (e.g. [`FamilyId`](https://community.torproject.org/relay/setup/post-install/family-ids/)) |
| `/var/log/oniondao.log` | Install log |

### Automatic updates

Once a day, at a random time per server, the timer fast-forwards `/opt/oniondao` to the latest release. If anything changed, it re-applies your configuration without prompting and without registering again. A checkout with local changes or a diverged history is left untouched.

- Logs: `journalctl -u oniondao-update`
- Off: `sudo oniondao autoupdate off`, or install with `--no-auto-update`

---

## Upgrading a node installed before 2026

Run `sudo oniondao update` as before. It moves the install to `/opt/oniondao`, keeps your settings, switches Tor to the Tor Project's repository and cleans up what old versions changed on the system. It also offers to turn on automatic updates.

**Ubuntu 20.04 nodes can't be upgraded in place.** The Tor Project no longer publishes packages for 20.04. The installer stops without changing anything and prints how to move your relay keys to a fresh server, so your relay keeps its identity.

---

## Development

- `shellcheck -x *.sh lib/*.sh test/*.sh`
- CI ([`.github/workflows/test.yml`](.github/workflows/test.yml)) installs a real relay on every supported distro and architecture, upgrades a seeded 2022 node, and checks that Ubuntu 20.04 is refused without changes. Test relays never join the network (`PublishServerDescriptor 0`) and register with a mock oracle.
- `test/verify.sh` asserts a healthy node; run it on any server after an install.
- Test a branch on a server: `curl -fsSL …/setup.sh | sudo ONIONDAO_REF=my-branch bash`

Video walkthrough of the original setup: [Rocketeer Discord](https://discord.com/channels/899629740766412890/959100274587344966/959193725458858064).

OnionDAO is not affiliated with the Tor Project or POAP.
