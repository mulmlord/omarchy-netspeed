# Net speed for Omarchy

An [Omarchy](https://omarchy.org) bar widget that shows live download and upload speed:

```
↓128KB ↑ 20KB
```

- The widget has a fixed width, so the bar doesn't shift as the numbers change. It dims while the network is idle.
- **Interfaces:** by default it follows whichever interfaces carry your default route (IPv4 or IPv6). Switching between Wi-Fi, Ethernet or USB tethering needs no setup, and Docker or libvirt bridges are not counted.
- **Hover** for the interface names, the peak over the last minute, and totals since boot.
- **Click** to open Omarchy's network panel. **Right-click** to run Omarchy's speed test.
- On a vertical bar it shrinks to an icon, and the numbers move to the tooltip.

It reads `/proc/net/dev`, `/proc/net/route` and `/proc/net/ipv6_route` inside the shell. It starts no processes while polling and makes no network requests.

## Requirements

Omarchy with shell plugins (Quickshell bar). Click and right-click use the built-in `omarchy.network` plugin.

## Install

```bash
omarchy plugin add https://github.com/mulmlord/omarchy-netspeed.git --enable
```

To place it next to another widget, e.g. `omarchy bar move mulm.netspeed --after omarchy.workspaces`.

Update with `omarchy plugin update mulm.netspeed`.

## Remove

```bash
omarchy plugin remove mulm.netspeed
```

This removes the widget from the bar and deletes its folder. The widget stores nothing anywhere else.

## Settings

| Setting | Default | |
|---|---|---|
| Update interval | 1000 ms | 500–5000 ms |
| Unit | Bytes | `Bytes`: KB/s, MB/s (1024-based) · `Bits`: Kb/s, Mb/s (1000-based) |
| Interfaces | empty | Comma-separated names (e.g. `wlan0,eth0`). Empty follows the default route |

IPC: `omarchy-shell mulm.netspeed get` prints the current rates as JSON.

## License

MIT
