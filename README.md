<p align="center">
  <img src="docs/banner.svg" alt="Net Pulse: a glowing network chip for the Omarchy bar" width="100%">
</p>

<p align="center">
  <a href="#install"><img alt="Omarchy plugin" src="https://img.shields.io/badge/Omarchy-bar%20widget-43f2a1?style=flat-square&labelColor=0b141d"></a>
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-efcc45?style=flat-square&labelColor=0b141d"></a>
  <a href="https://github.com/nixfred/omacpu"><img alt="Sibling of CPU Pulse" src="https://img.shields.io/badge/sibling-CPU%20Pulse-63c89e?style=flat-square&labelColor=0b141d"></a>
  <a href="https://github.com/nixfred/ram.plugin.omarchy"><img alt="Sibling of RAM Pulse" src="https://img.shields.io/badge/sibling-RAM%20Pulse-8d9dff?style=flat-square&labelColor=0b141d"></a>
  <img alt="No dependencies" src="https://img.shields.io/badge/deps-Python%203%20only-91a5b0?style=flat-square&labelColor=0b141d">
</p>

# Net Pulse

An animated, glowing network chip for the Omarchy top bar. Green on a clear path to the internet → yellow when latency, loss or a weak radio bite → dark red when nothing is carrying traffic. The chip wears a radio when you are on Wi-Fi and a wired jack when you are on Ethernet, and packets run its pins faster as throughput rises.

<p align="center">
  <img src="docs/bar.gif" alt="CPU Pulse, RAM Pulse and Net Pulse side by side on the Omarchy bar" width="480">
  <br>
  <sub>CPU Pulse, RAM Pulse and Net Pulse on one bar. Same chip, same colour language.</sub>
</p>

Left-click opens the dashboard. Right-click offers five saved readouts: throughput, signal or link speed, latency, network name, IP address.

Net Pulse is the sibling of [CPU Pulse](https://github.com/nixfred/omacpu) and [RAM Pulse](https://github.com/nixfred/ram.plugin.omarchy): same chip, same colours, same dashboard layout, so the three sit together on the bar. It replaces the stock `omarchy.network` widget in place and keeps its bar slot.

## The dashboard

<table>
  <tr>
    <td width="50%" valign="top"><img src="docs/overview.png" alt="Overview tab: hero chip, download and upload, latency, history and the path to the internet"></td>
    <td width="50%" valign="top"><img src="docs/interfaces.png" alt="Interfaces tab: a card per link with addresses, counters and NetworkManager settings"></td>
  </tr>
  <tr>
    <td valign="top"><b>Overview.</b> Hero chip, live download and upload, latency to the gateway and to the internet with packet loss, link or signal, your address, connectivity state, 1-hour / 24-hour / 7-day history, and a hop-by-hop path from this device through the gateway and DNS to the internet.</td>
    <td valign="top"><b>Interfaces.</b> A card for every link — Ethernet, Wi-Fi, tunnels, bridges — with its addresses, live rates, lifetime totals, errors and drops, and the saved NetworkManager profile: IPv4 and IPv6 method, DNS, autoconnect, metered flag, wake-on-LAN. Connect, disconnect, flip autoconnect, or open the full editor.</td>
  </tr>
  <tr>
    <td width="50%" valign="top"><img src="docs/talkers.png" alt="Talkers tab: processes ranked by open sockets with their remote hosts"></td>
    <td width="50%" valign="top"><img src="docs/readout.png" alt="Right-click readout picker with five modes" width="360"></td>
  </tr>
  <tr>
    <td valign="top"><b>Talkers.</b> The 24 processes holding the most open connections, eight per page, with a TCP/UDP split and the remote hosts each one is talking to, labelled LAN, tailnet or internet. Click a row to focus its existing window or attached Herdr / tmux pane.</td>
    <td valign="top"><b>Readout picker.</b> Right-click the chip to choose what lives beside it. Keys 1–5 pick a mode; the choice is saved to your bar layout.</td>
  </tr>
</table>

The **Wi-Fi** tab carries the live association — dBm and quality, channel, width and band, negotiated rates each way, Wi-Fi generation, transmit power, retries, failures and beacon loss, and how long the association has held — above every nearby network, grouped by name with its access-point count, ready to connect, forget or take a passphrase. Band pinning and the radio switch live there too.

The **Network lab** tab holds every resolver systemd-resolved is using per link, with one-click DHCP / Cloudflare / Google switching and a cache flush; a 10-ping latency burst with jitter, a public-address lookup, a connectivity re-check and the speed test; then the transport counters — established connections, retransmits, new connections per second, socket pools, listening ports, resets — and the routing table.

The **Data** tab answers "how much have I used": bytes down and up over the last hour, day, week, month, year, or everything ever recorded, as a stacked bar per bucket with per-bucket hover readings, plus the daily average, the down/up split and the same totals broken out per interface. It also says how much of the window was actually recorded, so a fresh install reads "2d 8h recorded of 30d 0h" rather than implying a quiet month.

The **About** tab carries the version, a link to this repository and a link to [nixfred.com](https://nixfred.com). Version, repository and homepage all come from `manifest.json` through the shell's plugin registry, so a release is one edit there. Click a link to open it in your browser; right-click to copy it instead.

## What it does

- Animated chip that knows what it is plugged into: signal arcs on Wi-Fi, a wired jack with a running link light on Ethernet, a broken ring when there is no route. Packet speed follows real throughput.
- Continuous 1-hour, 24-hour and 7-day history of download, upload, latency and signal, with the per-bucket download peak as a faint envelope and hover readings. Missing history is left blank; shutdowns and recording gaps break the trace.
- Data used, down and up, over the last hour, day, week, month, year or all time, bucketed into bars you can hover and split by interface. Totals survive reboots because they are summed from measured rates, not read from counters that reset.
- Wi-Fi that reads like a radio should: dBm and quality, channel and width, the band, negotiated rates each way, Wi-Fi 4/5/6/7, transmit power, retries, failures and beacon loss, and how long this association has held.
- Connect, disconnect and forget networks; WPA and WPA3 passphrases; pin the 2.4, 5 or 6 GHz band or hand it back to automatic; turn the radio off; share the current network as a QR code. An enterprise (802.1X) network opens the system connection editor, which is where its CA certificate, EAP method and server name belong.
- Every interface with its own card, including tunnels like Tailscale and WireGuard, and the saved NetworkManager profile behind it.
- Processes ranked by open sockets with their remote endpoints classified as LAN, tailnet or internet.
- Click any address — yours, the gateway, the resolver, a route's next hop, an interface's IPv4 or IPv6 — to copy it to the clipboard.
- DNS provider switching through `omarchy-dns` and a resolver cache flush, both the same paths the stock widget uses.

There are no process termination, firewall, route, sysctl or privileged tuning actions. Processes and window identities are revalidated on every focus click. Session routing uses argument arrays and validated IDs, never interpolated shell commands. DNS provider and band names are checked against fixed lists and connection IDs against a UUID pattern. Passphrases travel over D-Bus and never appear in a command line or in this plugin's state. This plugin does not create 802.1X profiles: writing their password through nmcli's interactive editor would persist it to the shell's nmcli history, and a profile built without a CA certificate and server-name check can be harvested by a rogue access point, so that setup is handed to the system editor instead.

## Install

Requires an existing Omarchy Quickshell desktop, Python 3, systemd user services, Hyprland and NetworkManager. No additional Python packages. `iw` is used for radio detail; without it the Wi-Fi tab still works from NetworkManager data.

```sh
git clone https://github.com/nixfred/omanet.plugin.omarchy.git
cd omanet.plugin.omarchy
python3 install.py
```

Installs under `~/.config/omarchy/plugins/nixfred.net-pulse`, takes the stock `omarchy.network` widget's slot in the bar (appending to the far right if that widget is not present), and enables `net-pulse.service` for the graphical session. Existing files and the bar layout are backed up under `~/.local/state/omarchy/backups/net-pulse-TIMESTAMP/`.

Throughput is sampled and timestamped at the counter read, so a slow collection pass cannot be charged to the interval. Each history sample stores the span it actually covered, and range totals are the sum of rate times span at full resolution, so bucketing cannot change the answer. Retention only prunes when a new timestamp is continuous with what is stored, so a clock corrected forward cannot erase real history.

The recorder runs independently of the shell and popup: throughput and pings every 2 seconds, NetworkManager and Wi-Fi state every 6, sockets every 9, DNS and routes every 15, history every 15. SQLite retains seven days (up to 40,320 samples), downsampled to ~240 points per displayed range; per-bucket peaks are retained. State is private (`0700` directory / `0600` files) in `$XDG_STATE_HOME/net-pulse` or `~/.local/state/net-pulse`. History stores aggregate metrics only — no addresses, host names or process identities. The latest snapshot contains process names, PIDs, window titles and remote addresses, and is replaced, not logged. Closed panels stop their large animations, and Wi-Fi scanning runs only while the Wi-Fi tab is open.

## Controls and diagnosis

```sh
omarchy-shell nixfred.net-pulse open
omarchy-shell nixfred.net-pulse modes
omarchy-shell nixfred.net-pulse status
omarchy-shell nixfred.net-pulse rescan
omarchy-shell nixfred.net-pulse showTab 4            # 0-6: overview, wi-fi, interfaces, talkers, data, lab, about
omarchy-shell nixfred.net-pulse dataRange 2592000    # 3600, 86400, 604800, 2592000, 31536000, or 0 for all time
systemctl --user status net-pulse.service
journalctl --user -u net-pulse.service
python3 net_pulse.py snapshot          # one-shot JSON, no daemon needed
python3 -m unittest discover -s tests -v
node tests/test_model.cjs
qmltestrunner -input tests/tst_widgets.qml
omarchy plugin validate .
```

Left/right arrows change dashboard tabs. Escape closes. Keys 1–5 select modes in the right-click picker. Inline bar setting `animated: false` disables chip animations.

Disable with `omarchy plugin disable nixfred.net-pulse` and `systemctl --user disable --now net-pulse.service`. This stops only this plugin's telemetry service; historical data stays available. Restore the timestamped `shell.json` backup to bring the stock network widget back to its slot.

## Accounting

Throughput is the delta of `/proc/net/dev` byte counters over the sampling interval, so it counts framed bytes on the interface, not payload. Units are decimal: 1 MB/s is 1,000,000 bytes per second, matching how link rates and speed tests are quoted. A counter reset or a newly appeared interface reads zero rather than a spike.

Data used is the same measurement integrated over time: each sample's rate multiplied by the interval it actually covered, summed at full resolution so the number does not change with how coarsely the bars are bucketed. Because it is built from rates rather than from `/proc/net/dev` totals, a reboot, a counter reset or a renamed interface does not reset it. Nothing is recorded while the collector is stopped, and that missing time is excluded from the averages rather than counted as idle — which is why every range also reports how much of itself was recorded. The last hour is read from the 15-second samples, which are kept for seven days; every longer range comes from an hourly per-interface rollup kept for five years, at one row per hour per interface. Buckets align to the local clock, so a day starts at midnight here and not at midnight UTC. Traffic inside a tunnel is counted on both the tunnel and the interface carrying it, exactly as the kernel counts it, so per-interface figures can legitimately sum to more than what left the machine.

Latency is a single `ping` per probe cycle to the default gateway and to a public resolver, averaged over the last 24 samples. The probe follows the address family carrying the default route, so an IPv6-only host is measured over IPv6 rather than reported as offline. A timed-out probe is kept as a loss, not dropped, so the loss percentage is real; `null` means no sample has come back yet, which is different from a timeout. The gateway probe measures your local link, the internet probe measures the whole path.

Wi-Fi signal in dBm comes from `iw`; the 0–100 quality is NetworkManager's own figure for the associated access point. Negotiated rates are the current PHY rates, which is the ceiling of what the radio could carry, not what you are using. Nearby networks are grouped by name: one row can stand for several access points, and its channel, band and rate come from the strongest one.

The bar readout holds a fixed width per mode rather than shrinking to each reading. A widget that changes width every two seconds re-lays out the whole bar section it sits in, and on a crowded bar the sections overlap while the shell settles, so the readout ends up drawn over its neighbour. Each mode reserves the width of the widest string it can produce; the live text still wins if it ever runs wider, so nothing is clipped. The network name and IP address modes reserve nothing, because they only change when the network does.

Socket counts come from `ss` and are exact. Per-process bandwidth is deliberately absent: attributing bytes to a process needs packet capture privileges this plugin does not take. RSS-style double counting does not apply here, but a process holding many sockets to one host is not necessarily using more bandwidth than one holding a single busy socket.

References: [/proc/net/dev](https://docs.kernel.org/networking/statistics.html), [NetworkManager](https://networkmanager.dev/docs/api/latest/), [systemd-resolved](https://www.freedesktop.org/software/systemd/man/latest/resolvectl.html), [iw](https://wireless.wiki.kernel.org/en/users/documentation/iw), [Quickshell.Networking](https://quickshell.org/docs/master/types/Quickshell.Networking/).

## Layout

- **`Panel.qml`** — bar widget, seven-tab dashboard, readout picker, Wi-Fi actions, IPC handler
- **`NetChip.qml`** — the animated chip, compact on the bar and large in the hero card
- **`HistoryGraph.qml`** — throughput and latency history with peak envelope and hover
- **`UsageGraph.qml`** — data used per bucket, download and upload stacked, with hover
- **`Model.js`** — colour ramp, health score, formatting, readout modes, bar width reservations
- **`net_pulse.py`** — telemetry daemon, SQLite history and usage rollup, focus and network actions
- **`install.py`** — copies the plugin, enables the service, takes the network widget's bar slot with backups
- **`tests/`** — Python unit tests, a Node check of the model helpers, and QML widget tests

## License

MIT. See [LICENSE](LICENSE).
