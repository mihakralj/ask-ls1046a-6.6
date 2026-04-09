# ASK for NXP LS1046A — Linux 6.6 LTS

NXP Application Solutions Kit (ASK) — hardware-accelerated packet processing for **NXP LS1046A** (and LS1043A) Layerscape processors. Ported to **mainline Linux 6.6 LTS**.

This repository is a complete, self-contained fork of [ASK](https://github.com/we-are-mono/ASK) with kernel patches adapted for Linux 6.6.x. It includes kernel modules, userspace daemons, build patches, and configuration files needed to enable DPAA fast-path offloading.

## Quick Start

```bash
# 1. Apply kernel patches
./scripts/apply.sh /path/to/linux-6.6.x

# 2. Build kernel
cd /path/to/linux-6.6.x
make olddefconfig && make -j$(nproc)

# 3. Build out-of-tree modules (against patched kernel)
cd /path/to/ask-ls1046a-6.6/cdx && make KERNEL_DIR=/path/to/linux-6.6.x
cd /path/to/ask-ls1046a-6.6/fci && make KERNEL_DIR=/path/to/linux-6.6.x
cd /path/to/ask-ls1046a-6.6/auto_bridge && make KERNEL_DIR=/path/to/linux-6.6.x

# 4. Build userspace (cmm, dpa_app)
cd /path/to/ask-ls1046a-6.6/cmm && ./configure && make
cd /path/to/ask-ls1046a-6.6/dpa_app && make
```

## Repository Structure

```
ask-ls1046a-6.6/
├── patches/                          — All patches
│   ├── kernel/
│   │   ├── 003-ask-kernel-hooks.patch   — Mainline 6.6 kernel hooks (75 files)
│   │   └── sdk-sources/                 — NXP SDK driver sources (67 files)
│   │       ├── drivers/net/ethernet/freescale/sdk_dpaa/   (11 files)
│   │       ├── drivers/net/ethernet/freescale/sdk_fman/   (48 files)
│   │       ├── drivers/staging/fsl_qbman/                 (4 files)
│   │       └── include/                                   (4 files)
│   ├── fmlib/                        — fmlib ASK extensions patch
│   ├── fmc/                          — fmc ASK extensions patch
│   ├── iptables/                     — QOSMARK xtables extensions
│   ├── libnetfilter-conntrack/       — Fast-path conntrack attributes
│   ├── libnfnetlink/                 — Non-blocking heap buffer fix
│   ├── iproute2/                     — EtherIP/4RD tunnel support
│   ├── ppp/                          — PPP ifindex support
│   └── rp-pppoe/                     — CMM relay support
│
├── cdx/                              — CDX kernel module (184 files)
│                                       Core driver: /dev/cdx_ctrl, FMAN hash table mgmt
├── fci/                              — FCI kernel module (32 files)
│                                       Fast-path Classification Interface
├── auto_bridge/                      — Auto-bridge kernel module (5 files)
│                                       L2 bridge flow auto-offload
├── cmm/                              — CMM daemon (251 files)
│                                       Conntrack monitoring, flow offload to FMAN
├── dpa_app/                          — DPA application (14 files)
│                                       One-shot FMAN PCD programmer (reads cdx_pcd.xml)
│
├── config/                           — Configuration files
│   ├── ask.config                    — Kernel config fragment
│   ├── ask-modules.conf              — Module load order (systemd-modules-load)
│   ├── cmm.service                   — CMM systemd unit
│   ├── fastforward                   — Traffic exclusion rules (FTP/SIP/PPTP)
│   ├── gateway-dk/cdx_cfg.xml        — Port-to-policy mapping (5 ports + 2 offline)
│   └── kernel/defconfig              — Reference ASK kernel defconfig
│
├── scripts/
│   └── apply.sh                      — Apply kernel patches to a kernel tree
│
└── README.md                         — This file
```

## What Changed from ASK

| Component | ASK (upstream) | ask-ls1046a-6.6 (this repo) |
|-----------|---------------|---------------------|
| Kernel patch target | Linux 6.12 (NXP SDK kernel) | **Linux 6.6 LTS (mainline)** |
| Kernel patch | `002-mono-gateway-ask-kernel_linux_6_12.patch` | `003-ask-kernel-hooks.patch` + `sdk-sources/` |
| SDK sources | Embedded in NXP kernel tree | **Extracted as separate files** (67 files in `patches/kernel/sdk-sources/`) |
| Userspace (cdx, fci, cmm, etc.) | Same | **Identical** — copied unchanged |
| Userspace patches | Same | **Identical** — copied unchanged |
| Config files | Same | **Identical** — copied unchanged |

The kernel patch is **split into two parts** for maintainability:
- **SDK sources** (67 files) — NXP SDK drivers that don't exist in mainline. Static, never change.
- **Hooks patch** (75 files) — Modifications to standard kernel subsystems. Tested against mainline v6.6 with **0 failures**.

## Kernel Patch Details

### SDK Sources (67 files — injected into kernel tree)

| Directory | Files | Description |
|-----------|-------|-------------|
| `sdk_dpaa/` | 11 | SDK DPAA Ethernet: fast-path TX/RX, buffer pools, offline port, CEETM |
| `sdk_fman/` | 48 | SDK Frame Manager: PCD classifier, enhanced hash tables (ehash), port/MAC |
| `fsl_qbman/` | 4 | QBMan portal NAPI, QMan enqueue, USDPAA |
| `include/` | 4 | `fsl_oh_port.h`, `fsl_qman.h`, FMD UAPI headers |

### Hooks Patch (75 files — applied via `patch -p1`)

| Subsystem | Files | What's Added |
|-----------|-------|-------------|
| Netfilter | 8 (3 new) | `comcerto_fp_netfilter.c`, QoS mark/connmark extensions |
| Bridge | 7 | L2 fast-path notifications (FDB, STP, VLAN) |
| net/core | 4 | `cpe_fp_tx()` in `__dev_queue_xmit`, SKB recycling |
| XFRM/IPsec | 8 (2 new) | `ipsec_flow.c/.h`, SA/SP hardware offload lifecycle |
| IPv4/IPv6 | 10 | Fast-path forwarding, tunnel hooks, ESP6 |
| Headers | 26 | `fp_info` in `sk_buff`/`net_device`/`nf_conn`, UAPI extensions |
| Drivers | 3 | CAAM IPsec, PPP/PPPoE hooks, USB net |
| Build | 9 | Kconfig, Makefile additions |

## How ASK Works

1. **First packet** goes through Linux kernel (slow path, conntrack)
2. **CMM daemon** monitors conntrack for established flows
3. CMM programs **FMAN hardware hash tables** via CDX kernel module
4. **Subsequent packets** forwarded entirely in hardware — zero CPU
5. Flow expires in conntrack → CMM removes hardware entry

Supported: TCP/UDP/ESP/PPPoE/L2 bridge/multicast/NAT flows.

## Hardware Requirements

- **SoC:** NXP LS1046A (or LS1043A with FMAN)
- **FMAN Microcode:** ASK version **v210.10.1** (enhanced hash table instructions)
- Standard FMAN microcode will NOT work — degrades gracefully to software forwarding

## Kernel Config

The `config/ask.config` fragment enables:

```
CONFIG_CPE_FAST_PATH=y          # Core fast-path engine
CONFIG_FSL_SDK_DPA=y            # NXP SDK DPAA driver
CONFIG_FSL_SDK_DPAA_ETH=y       # SDK DPAA Ethernet (replaces mainline)
CONFIG_FSL_DPAA_1588=y          # IEEE 1588 timestamping
CONFIG_NETFILTER_XT_QOSMARK=y   # iptables QOSMARK target
CONFIG_NETFILTER_XT_QOSCONNMARK=y
CONFIG_INET_IPSEC_OFFLOAD=y    # IPsec offload hooks
CONFIG_MODVERSIONS=y            # Module versioning
# CONFIG_FSL_DPAA_ETH is not set  # Disable conflicting mainline driver
```

## External Dependencies

These are cloned and patched during the userspace build:

| Component | Repository | Patch |
|-----------|-----------|-------|
| fmlib | `github.com/nxp-qoriq/fmlib` | `patches/fmlib/` |
| fmc | `github.com/nxp-qoriq/fmc` | `patches/fmc/` |
| libcli | `github.com/dparrish/libcli` | None |
| iptables | `apt-get source iptables` | `patches/iptables/` |
| libnetfilter-conntrack | `apt-get source` | `patches/libnetfilter-conntrack/` |
| libnfnetlink | `apt-get source` | `patches/libnfnetlink/` |
| iproute2 | `apt-get source` | `patches/iproute2/` |
| ppp | `apt-get source` | `patches/ppp/` |
| rp-pppoe | `apt-get source` | `patches/rp-pppoe/` |

## Compatibility

| Kernel | Status |
|--------|--------|
| Linux 6.6.x (any point release) | ✅ Tested against v6.6 with 0 failures |
| Linux 6.1.x, 5.15.x | ❌ Not tested — use ASK patches for those versions |
| Linux 6.12.x | Use upstream [ASK](https://github.com/we-are-mono/ASK) directly |

## License

GPL-2.0, consistent with Linux kernel licensing. See individual source files for copyright notices.

## Origin

Ported from [ASK](https://github.com/we-are-mono/ASK) (kernel 6.12) to mainline Linux 6.6 LTS. NXP SDK sources extracted from `nxp-qoriq/linux` tag `lf-6.6.52-2.2.0`. Userspace sources, patches, and configs are unchanged from upstream ASK.