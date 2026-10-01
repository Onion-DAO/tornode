# Changelog

## [1.0.0] - 2026-10-01

### Breaking
- support Ubuntu 26.04/24.04 + Debian 13/12 (amd64/arm64), 20.04 refused safely (204bb54)
- install to `/opt/oniondao`, settings in `/etc/oniondao/oniondao.conf` (204bb54)

### Added
- daily auto-update via systemd timer, on by default, `oniondao autoupdate on|off` (204bb54)
- `oniondao update` offers to enable auto-update (204bb54)
- unattended mode: `--yes` + `ONIONDAO_*` variables, works with `curl | sudo bash` (204bb54)
- local unbound DNSSEC resolver for exit traffic, `--no-unbound` to skip (204bb54)
- `/etc/tor/torrc.d/*.conf` for own Tor options, kept across updates (204bb54)
- `oniondao debug` diagnostics, `status` shows update availability (204bb54)
- CI installs a real relay per distro/arch, upgrades a 2022 node, checks refusal (e313b63)

### Changed
- Tor from deb.torproject.org (deb822, verified key), 0.4.9+ enforced (204bb54)
- torrc: ReducedExitPolicy, IPv6 auto-bind, CIISS ContactInfo, validated + rollback (204bb54)
- exit notice from Tor's packaged template, wallet comment unchanged (204bb54)
- old installs migrate on `oniondao update`, incl. apt/unattended-upgrades cleanup (204bb54)
- registration payload built with jq, oracle verdict parsed from status and body (204bb54)

### Fixed
- install never worked on current distros (dead focal repo, apt-key, pip, ntpdate) (204bb54)
- nyx pip fallback and IPv6 disable checks were constant expressions (204bb54)
- IP lookup fallbacks never ran, `$HOME`/`$USER` under sudo pointed at root (204bb54)
- clones failed on machines with git-lfs (dead video LFS pointer) (394481e)
- unbound failed under the old no-recommends rule (40c5399)
- automatic updates stalled on accepted untested releases (2539623)

### Removed
- downloads from the discontinued tor-relay.co configurator (204bb54)
- system-wide `40norecommends` apt rule of old versions (40c5399)
