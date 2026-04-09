#!/usr/bin/env bash
# apply.sh — Apply ASK patches to a Linux 6.6.x LTS kernel source tree
#
# Usage:
#   ./scripts/apply.sh /path/to/linux-6.6.x
#
# This script:
#   1. Copies NXP SDK driver sources into the kernel tree (67 files)
#   2. Applies the kernel hooks patch (75 files)
#   3. Appends the ASK kernel config fragment
#
# Prerequisites:
#   - Linux 6.6.x LTS kernel source tree (any 6.6.x version)
#   - patch, cp, cat utilities
#
# The NXP SDK sources do NOT exist in mainline Linux — they are NXP-only
# additions (sdk_dpaa, sdk_fman, fsl_qbman). The hooks patch modifies
# standard kernel subsystems (netfilter, bridge, xfrm, net/core, etc.).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SDK_DIR="$REPO_DIR/sdk-sources"
PATCH="$REPO_DIR/kernel-patch/003-ask-kernel-hooks.patch"
CONFIG="$REPO_DIR/config/ask.config"

# --- Argument handling ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 /path/to/linux-6.6.x [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Test patch application without modifying files"
    exit 1
fi

KERNEL_DIR="$1"
DRY_RUN="${2:-}"

# --- Validate kernel tree ---
if [ ! -f "$KERNEL_DIR/Makefile" ]; then
    echo "ERROR: $KERNEL_DIR does not appear to be a Linux kernel source tree"
    echo "       (no Makefile found)"
    exit 1
fi

KVER=$(grep '^VERSION' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
KPATCH=$(grep '^PATCHLEVEL' "$KERNEL_DIR/Makefile" | head -1 | awk '{print $3}')
echo "Detected kernel: $KVER.$KPATCH.x"

if [ "$KVER" != "6" ] || [ "$KPATCH" != "6" ]; then
    echo "WARNING: This patch was developed for Linux 6.6.x LTS"
    echo "         Detected: $KVER.$KPATCH.x — hunks may not apply cleanly"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# --- Dry-run mode ---
if [ "$DRY_RUN" = "--dry-run" ]; then
    echo ""
    echo "=== DRY RUN: Testing kernel hooks patch ==="
    FAILURES=$(patch --dry-run -p1 --no-backup-if-mismatch -d "$KERNEL_DIR" < "$PATCH" 2>&1 | grep -c 'FAILED' || true)
    if [ "$FAILURES" -gt 0 ]; then
        echo ""
        echo "FAILED: $FAILURES hunks would not apply cleanly"
        echo "Run with full output to see details:"
        echo "  patch --dry-run -p1 -d $KERNEL_DIR < $PATCH"
        exit 1
    else
        echo "SUCCESS: All hunks apply cleanly (dry-run)"
        echo ""
        echo "=== DRY RUN: Checking SDK source paths ==="
        CONFLICTS=0
        while IFS= read -r f; do
            target="$KERNEL_DIR/$f"
            if [ -f "$target" ]; then
                echo "  CONFLICT: $f already exists in kernel tree"
                CONFLICTS=$((CONFLICTS + 1))
            fi
        done < <(cd "$SDK_DIR" && find . -type f -printf '%P\n')
        if [ "$CONFLICTS" -gt 0 ]; then
            echo "WARNING: $CONFLICTS SDK files already exist — they will be overwritten"
        else
            echo "OK: No SDK file conflicts"
        fi
    fi
    exit 0
fi

# --- Step 1: Copy NXP SDK sources ---
echo ""
echo "=== Step 1/3: Copying NXP SDK sources (67 files) ==="
SDK_COUNT=0
while IFS= read -r f; do
    target="$KERNEL_DIR/$f"
    mkdir -p "$(dirname "$target")"
    cp "$SDK_DIR/$f" "$target"
    SDK_COUNT=$((SDK_COUNT + 1))
done < <(cd "$SDK_DIR" && find . -type f -printf '%P\n')
echo "  Copied $SDK_COUNT files"

# --- Step 2: Apply kernel hooks patch ---
echo ""
echo "=== Step 2/3: Applying kernel hooks patch (75 files) ==="
patch --no-backup-if-mismatch -p1 -d "$KERNEL_DIR" < "$PATCH"
echo "  Patch applied successfully"

# --- Step 3: Append kernel config ---
echo ""
echo "=== Step 3/3: Appending ASK kernel config ==="

# Find defconfig or .config
if [ -f "$KERNEL_DIR/.config" ]; then
    CONFIG_TARGET="$KERNEL_DIR/.config"
    echo "  Appending to .config"
elif [ -f "$KERNEL_DIR/arch/arm64/configs/defconfig" ]; then
    CONFIG_TARGET="$KERNEL_DIR/arch/arm64/configs/defconfig"
    echo "  Appending to arch/arm64/configs/defconfig"
else
    CONFIG_TARGET=""
    echo "  No .config or defconfig found — manual config required"
    echo "  Append the contents of config/ask.config to your kernel config"
fi

if [ -n "$CONFIG_TARGET" ]; then
    # Remove conflicting mainline DPAA ETH if enabled
    if grep -q '^CONFIG_FSL_DPAA_ETH=y' "$CONFIG_TARGET" 2>/dev/null; then
        sed -i 's/^CONFIG_FSL_DPAA_ETH=y/# CONFIG_FSL_DPAA_ETH is not set/' "$CONFIG_TARGET"
        echo "  Disabled conflicting CONFIG_FSL_DPAA_ETH"
    fi
    echo "" >> "$CONFIG_TARGET"
    cat "$CONFIG" >> "$CONFIG_TARGET"
    echo "  Config fragment appended"
fi

# --- Done ---
echo ""
echo "=== ASK patch applied successfully ==="
echo ""
echo "Next steps:"
echo "  1. cd $KERNEL_DIR"
echo "  2. make olddefconfig    # resolve new config options"
echo "  3. make -j\$(nproc)      # build kernel"
echo ""
echo "For out-of-tree ASK modules (cdx.ko, fci.ko, auto_bridge.ko),"
echo "see the ASK repo: https://github.com/we-are-mono/ASK"