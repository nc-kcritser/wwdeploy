#!/bin/bash
#
# Install DOCA-OFED in Warewulf container shell
# Handles kernel mismatch by letting dnf install fail (registers DKMS modules),
# then manually builds modules for the container's actual kernel.
#
# Usage: ./install-doca-ofed-container.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect container kernel
RUNNING_KERNEL=$(uname -r)
log_info "Running kernel (headnode): $RUNNING_KERNEL"

# Check /lib/modules for actual container kernel
CONTAINER_MOD_DIR=$(ls -d /lib/modules/5.14.0-* 2>/dev/null | head -1)
if [ -z "$CONTAINER_MOD_DIR" ]; then
    log_error "No kernel modules directory found in /lib/modules/"
    exit 1
fi

CONTAINER_KERNEL=$(basename "$CONTAINER_MOD_DIR")
log_info "Container filesystem kernel: $CONTAINER_KERNEL"

if [ "$RUNNING_KERNEL" = "$CONTAINER_KERNEL" ]; then
    log_warn "Running and filesystem kernels match—DKMS should work normally"
fi

# Step 1: Install DOCA-OFED (will fail on DKMS, but registers modules)
log_info "Installing DOCA-OFED packages (DKMS errors expected)..."
dnf install -y doca-ofed 2>&1 | tee /tmp/doca-install.log || {
    log_warn "dnf install exited with error (expected). Checking if DKMS modules registered..."
}

# Step 2: Check what modules are registered
log_info "Checking DKMS status..."
dkms status

# Step 3: Build each module for the container's actual kernel
log_info "Building DKMS modules for kernel $CONTAINER_KERNEL..."

# Extract modules dynamically from dkms status (format: module/version)
MODULES=$(dkms status | awk '{print $1}' | sort -u)

if [ -z "$MODULES" ]; then
    log_error "No DKMS modules found!"
    exit 1
fi

FAILED=0
for module in $MODULES; do
    log_info "Installing $module for $CONTAINER_KERNEL..."
    if dkms install "$module" -k "$CONTAINER_KERNEL"; then
        log_info "✓ $module installed successfully"
    else
        log_warn "✗ $module installation failed (may already be built or not applicable)"
        ((FAILED++))
    fi
done

# Step 4: Verify all modules
log_info "Final DKMS status:"
dkms status

if [ $FAILED -eq 0 ]; then
    log_info "✓ DOCA-OFED installation complete!"
else
    log_warn "⚠ $FAILED module(s) failed to install (check output above)"
fi

log_info "Next step: dnf install -y nvidia-driver-open-dkms (when ready)"