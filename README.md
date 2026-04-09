# ASK Kernel Patch for Linux 6.6.x LTS

NXP Application Solutions Kit (ASK) hardware packet offload for **NXP LS1046A** (and compatible QorIQ Layerscape SoCs with FMAN silicon). Ported to mainline Linux 6.6 LTS.

ASK offloads established network flows (TCP/UDP/ESP/PPPoE/L2 bridge) to the FMAN hardware classifier — **zero CPU cost** for matched flows, wire-rate forwarding on 10G ports.

## Quick Start

```bash
# Clone this repo
git clone https://github.com/we-are-mono/ask_6.6.git

# Get a Linux 6.6.x kernel source tree
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.75.tar.xz
tar xf linux-6.6.75.tar.xz

# Test (dry-run — no files modified)
./ask_6.6/scripts/apply.sh linux-6.6.75 --dry-run

# Apply
./ask_6.6/scripts/apply.sh linux-6.6.75

# Build
cd linux-6.6.75
make olddefconfig
make -j$(nproc)
```

## What This Does

The ASK kernel modification is split into two parts:

### 1. NXP SDK Sources (67 files — injected)

NXP SDK driver sources that **do not exist in mainline Linux**. These are copied directly into the kernel tree:

| Directory | Files | Description |
|-----------|-------|-------------|
| `drivers/net/ethernet/freescale/sdk_dpaa/` | 11 | SDK DPAA Ethernet driver (fast-path TX/RX, buffer pools, offline port) |
| `drivers/net/ethernet/freescale/sdk_fman/` | 48 | SDK Frame Manager driver (PCD classifier, enhanced hash tables, port/MAC control) |
| `drivers/staging/fsl_qbman/` | 4 | QBMan portal NAPI, QMan enqueue, USDPAA updates |
| `include/linux/fsl_oh_port.h` | 1 | Offline port header |
| `include/uapi/linux/fmd/` | 3 | FMD UAPI headers |

These files are **static** — they come from the NXP SDK kernel and do not change between 6.6.x point releases.

### 2. Kernel Hooks Patch (75 files — patched)

A `patch -p1` format patch that modifies standard kernel subsystems to add ASK fast-path hooks:

| Subsystem | Files | What's Added |
|-----------|-------|-------------|
| **Netfilter** | 8 (3 new) | `comcerto_fp_netfilter.c` fast-path engine, `xt_qosmark.c`/`xt_qosconnmark.c` QoS extensions, conntrack flow-info hooks |
| **Bridge** | 7 | L2 fast-path notifications on FDB learn/age, STP state, VLAN changes |
| **net/core** | 4 | `cpe_fp_tx()` hook in `__dev_queue_xmit`, SKB recycling, rtnetlink notifications |
| **XFRM/IPsec** | 8 (2 new) | `ipsec_flow.c/.h` SA/SP lifecycle tracking for hardware IPsec offload |
| **IPv4** | 3 | Fast-path forwarding, IPsec output offload, tunnel hooks |
| **IPv6** | 7 | Fast-path, SIT/IP6 tunnel support, ESP6, UDP extensions |
| **Kernel headers** | 9 | `fp_info` struct in `sk_buff`, `net_device`, `nf_conn` for flow metadata |
| **UAPI headers** | 17 (4 new) | QoS mark structs, fast-path conntrack attributes, tunnel extensions |
| **Drivers** | 3 | CAAM `pdb.h` IPsec structures, PPP/PPPoE fast-path hooks, USB net hook |
| **Build system** | 4 | Root Makefile SUBDIRS compat, Kconfig additions in net/ |
| **Other** | 5 | Wireless Kconfig, `tools/perf/.gitignore` |

This patch was tested against **mainline Linux v6.6** (kernel.org) with **0 failures**.

## Repository Structure

```
ask_6.6/
├── README.md                  — This file
├── config/
│   └── ask.config             — Kernel config fragment (append to defconfig)
├── kernel-patch/
│   └── 003-ask-kernel-hooks.patch  — 75-file mainline-compatible patch (172KB)
├── sdk-sources/               — 67 NXP SDK source files (681KB)
│   ├── drivers/
│   │   ├── net/ethernet/freescale/
│   │   │   ├── sdk_dpaa/      — SDK DPAA Ethernet driver
│   │   │   └── sdk_fman/      — SDK Frame Manager driver
│   │   └── staging/fsl_qbman/ — QBMan portal/USDPAA
│   └── include/
│       ├── linux/fsl_oh_port.h
│       └── uapi/linux/fmd/    — FMD UAPI headers
└── scripts/
    └── apply.sh               — Apply everything to a kernel tree
```

## Kernel Config

The `config/ask.config` fragment enables:

| Symbol | Purpose |
|--------|---------|
| `CONFIG_CPE_FAST_PATH=y` | Core ASK fast-path engine |
| `CONFIG_FSL_SDK_DPA=y` | NXP SDK DPAA platform driver |
| `CONFIG_FSL_SDK_DPAA_ETH=y` | NXP SDK DPAA Ethernet (replaces mainline `FSL_DPAA_ETH`) |
| `CONFIG_FSL_DPAA_1588=y` | IEEE 1588 timestamping |
| `CONFIG_NETFILTER_XT_QOSMARK=y` | iptables QOSMARK target |
| `CONFIG_NETFILTER_XT_QOSCONNMARK=y` | iptables QOSCONNMARK target |
| `CONFIG_INET_IPSEC_OFFLOAD=y` | IPsec hardware offload hooks |
| `CONFIG_MODVERSIONS=y` | Module versioning for out-of-tree modules |

**Important:** `CONFIG_FSL_SDK_DPAA_ETH` and mainline `CONFIG_FSL_DPAA_ETH` are mutually exclusive. The apply script automatically disables the mainline driver.

## How ASK Works

```
                    ┌─────────────────────────────────┐
                    │         FMAN Silicon             │
                    │  ┌─────────────────────────┐    │
  Packet  ──────►   │  │  PCD Hash Classifier    │    │
  arrives           │  │  (16 tables, 5-tuple)   │    │
                    │  └────────┬────────────────┘    │
                    │           │                      │
                    │     ┌─────▼─────┐                │
                    │     │ Match?    │                │
                    │     └─┬───────┬─┘                │
                    │   Yes │       │ No               │
                    │       ▼       ▼                  │
                    │  ┌────────┐ ┌──────────┐        │
                    │  │Hardware│ │Linux slow │        │
                    │  │forward │ │  path     │        │
                    │  │(0 CPU) │ │(conntrack)│        │
                    │  └────────┘ └─────┬────┘        │
                    └───────────────────┼──────────────┘
                                        │
                                   ┌────▼────┐
                                   │  CMM    │  Monitors conntrack,
                                   │ daemon  │  programs FMAN hash
                                   └─────────┘  tables for new flows
```

1. **First packet** of a flow goes through the Linux kernel (slow path)
2. **CMM daemon** monitors conntrack for established flows
3. CMM programs the **FMAN hardware hash tables** via the CDX kernel module
4. **Subsequent packets** are forwarded entirely in hardware — zero CPU involvement
5. When the flow expires in conntrack, CMM removes the hardware entry

## Supported Flow Types

| Flow Type | Hash Table | Key Size | Max Entries |
|-----------|-----------|----------|-------------|
| IPv4 TCP/UDP | 5-tuple | 14 bytes | 128 |
| IPv6 TCP/UDP | 5-tuple | 38 bytes | 128 |
| ESP/IPsec | SPI + address | Variable | 32 |
| L2 Bridge | MAC + VLAN | 15 bytes | 32 |
| PPPoE | Session ID + address | Variable | 32 |
| Multicast | Group + source | Variable | 32 |
| NAT 3-tuple | IP + port + proto | Variable | 32 |

## Hardware Requirements

- **SoC:** NXP LS1046A (or compatible QorIQ with FMAN)
- **FMAN Microcode:** ASK-specific version **v210.10.1** (programs enhanced hash tables)
- **Standard FMAN microcode will NOT work** — the enhanced hash table instructions are ASK-specific

Without ASK microcode, the system boots normally and operates as a standard Linux router with software forwarding. ASK degrades gracefully.

## Out-of-Tree Modules

This repo provides the **kernel patches only**. The ASK userspace components are built separately from the [ASK repository](https://github.com/we-are-mono/ASK):

| Module | Source | Purpose |
|--------|--------|---------|
| `cdx.ko` | `ASK/cdx/` | Core CDX driver — creates `/dev/cdx_ctrl`, manages FMAN hash tables |
| `fci.ko` | `ASK/fci/` | Fast-path Classification Interface — flow programming API |
| `auto_bridge.ko` | `ASK/auto_bridge/` | L2 bridge flow auto-offload |
| `dpa_app` | `ASK/dpa_app/` | One-shot FMAN PCD programmer (reads `cdx_pcd.xml`) |
| `cmm` | `ASK/cmm/` | Conntrack monitoring daemon — offloads established flows |

These modules are built against the patched kernel headers using standard out-of-tree kbuild (`make -C /lib/modules/$(uname -r)/build M=$PWD`).

## Compatibility

| Kernel | Status |
|--------|--------|
| Linux 6.6.0 (v6.6) | ✅ Tested — all hunks apply cleanly |
| Linux 6.6.x (any point release) | ✅ Expected to work — point releases have minimal changes |
| Linux 6.1.x, 5.15.x | ❌ Not tested — context lines will differ |
| Linux 6.12.x | Use the [6.12 patch](https://github.com/we-are-mono/ASK/tree/main/patches/kernel) instead |

## Distro Integration

### VyOS

```bash
# In your VyOS build system:
tar xzf ask-nxp-sdk-sources.tar.gz -C vyos-build/packages/linux-kernel/linux/
patch --no-backup-if-mismatch -p1 -d vyos-build/packages/linux-kernel/linux/ \
    < 003-ask-kernel-hooks.patch
cat config/ask.config >> vyos-build/.../vyos_defconfig
```

### Debian/Ubuntu

```bash
apt-get source linux-image-$(uname -r)
cd linux-6.6.*/
/path/to/ask_6.6/scripts/apply.sh .
make olddefconfig
make -j$(nproc) bindeb-pkg
```

### Yocto/OpenEmbedded

Add the SDK sources and patch to your kernel recipe's `SRC_URI` and `do_patch` steps.

## Origin

This patch was ported from the ASK kernel patch for Linux 6.12, originally developed by [Mindspeed Technologies / NXP](https://github.com/we-are-mono/ASK). The 6.12 patch targets the NXP SDK kernel (`nxp-qoriq/linux`). This 6.6 port was adapted for **mainline Linux** — no NXP kernel fork required.

The NXP SDK driver sources (`sdk_dpaa/`, `sdk_fman/`, `fsl_qbman/`) are extracted from the NXP kernel tree at tag `lf-6.6.52-2.2.0` with ASK modifications applied.

## License

The kernel patches and NXP SDK sources are licensed under **GPL-2.0**, consistent with the Linux kernel licensing. See individual source files for specific copyright notices.