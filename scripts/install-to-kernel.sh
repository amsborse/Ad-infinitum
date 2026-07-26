#!/usr/bin/env bash
# Copy Ad-infinitum fs/f2fs sources into a Linux kernel tree.
#
# Usage:
#   ./scripts/install-to-kernel.sh /path/to/linux-4.1.8
#
# After copying, enable CONFIG_F2FS_FS in the kernel config and rebuild.

set -euo pipefail

KERNEL_TREE="${1:?Usage: $0 /path/to/linux-kernel-tree}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_ROOT}/fs/f2fs"
DEST="${KERNEL_TREE}/fs/f2fs"

if [[ ! -d "${KERNEL_TREE}/fs" ]]; then
	echo "error: ${KERNEL_TREE} does not look like a Linux kernel source tree (missing fs/)" >&2
	exit 1
fi

if [[ ! -d "${SRC}" ]]; then
	echo "error: source directory not found: ${SRC}" >&2
	exit 1
fi

echo "Installing Ad-infinitum F2FS sources:"
echo "  from: ${SRC}"
echo "  to:   ${DEST}"

mkdir -p "${DEST}"
rsync -av --delete \
	--include='*.c' --include='*.h' --include='Makefile' --include='Kconfig' \
	--exclude='*' \
	"${SRC}/" "${DEST}/"

echo ""
echo "Done. Next steps:"
echo "  1. cd ${KERNEL_TREE}"
echo "  2. make menuconfig  → File systems → F2FS filesystem support"
echo "  3. make -j\$(nproc) && sudo make modules_install"
