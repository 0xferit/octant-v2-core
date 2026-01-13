#!/bin/bash
# Coverage script that patches Hats Protocol to avoid stack-too-deep errors
# during coverage instrumentation, runs coverage, then restores original files.

set -e

HATS_SOL="dependencies/hats-protocol-1.0/src/Hats.sol"
IHATS_SOL="dependencies/hats-protocol-1.0/src/Interfaces/IHats.sol"

# Cleanup function to restore files on exit (success or failure)
cleanup() {
    echo "Restoring original files..."
    [ -f "$HATS_SOL.bak" ] && mv "$HATS_SOL.bak" "$HATS_SOL"
    [ -f "$IHATS_SOL.bak" ] && mv "$IHATS_SOL.bak" "$IHATS_SOL"
}

# Set trap to ensure cleanup runs on exit
trap cleanup EXIT

# Check files exist
if [ ! -f "$HATS_SOL" ] || [ ! -f "$IHATS_SOL" ]; then
    echo "ERROR: Required Hats Protocol files not found"
    echo "Run 'forge soldeer install' first"
    exit 1
fi

echo "Patching Hats Protocol for coverage..."

# Comment out batchCreateHats function in Hats.sol (lines 184-226)
sed -i.bak '184,226s/^/\/\/ /' "$HATS_SOL"

# Comment out batchCreateHats declaration in IHats.sol (lines 38-46)
sed -i.bak '38,46s/^/\/\/ /' "$IHATS_SOL"

echo "Running forge coverage..."

# Run coverage with all arguments passed to this script
forge coverage "$@"
