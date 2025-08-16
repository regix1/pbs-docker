#!/bin/bash
set -e

# Environment variables with defaults
PBS_ENTERPRISE=${PBS_ENTERPRISE:-"no"}
PBS_NO_SUBSCRIPTION=${PBS_NO_SUBSCRIPTION:-"yes"}
DISABLE_SUBSCRIPTION_NAG=${DISABLE_SUBSCRIPTION_NAG:-"yes"}

echo "PBS Post-Install Configuration:"
echo "  PBS_ENTERPRISE=${PBS_ENTERPRISE}"
echo "  PBS_NO_SUBSCRIPTION=${PBS_NO_SUBSCRIPTION}"
echo "  DISABLE_SUBSCRIPTION_NAG=${DISABLE_SUBSCRIPTION_NAG}"

VERSION="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"

# Configure repositories
if [ "${PBS_ENTERPRISE}" = "no" ] || [ "${PBS_ENTERPRISE}" = "false" ]; then
    echo "Disabling enterprise repository..."
    echo "# deb https://enterprise.proxmox.com/debian/pbs ${VERSION} pbs-enterprise" > /etc/apt/sources.list.d/pbs-enterprise.list
fi

if [ "${PBS_NO_SUBSCRIPTION}" = "yes" ] || [ "${PBS_NO_SUBSCRIPTION}" = "true" ]; then
    echo "Enabling no-subscription repository..."
    echo "deb http://download.proxmox.com/debian/pbs ${VERSION} pbs-no-subscription" > /etc/apt/sources.list.d/pbs-install-repo.list
fi

# Disable subscription nag if requested
if [ "${DISABLE_SUBSCRIPTION_NAG}" = "yes" ] || [ "${DISABLE_SUBSCRIPTION_NAG}" = "true" ]; then
    echo "Disabling subscription nag in UI..."
    
    # Primary target file
    PROXMOXLIB="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    
    # Enhanced wait with timeout
    WAIT_COUNT=0
    MAX_WAIT=60
    while [ ! -f "$PROXMOXLIB" ] && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        echo "Waiting for proxmoxlib.js... ($WAIT_COUNT/$MAX_WAIT)"
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done
    
    if [ ! -f "$PROXMOXLIB" ]; then
        echo "ERROR: proxmoxlib.js not found after ${MAX_WAIT} seconds"
        exit 1
    fi
    
    echo "Found proxmoxlib.js at: $PROXMOXLIB"
    
    # Create original backup if not exists
    if [ ! -f "${PROXMOXLIB}.original" ]; then
        cp "$PROXMOXLIB" "${PROXMOXLIB}.original"
        echo "Created original backup: ${PROXMOXLIB}.original"
    fi
    
    # Create timestamped backup
    BACKUP="${PROXMOXLIB}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$PROXMOXLIB" "$BACKUP"
    echo "Created backup: $BACKUP"
    
    # Apply ALL patches comprehensively
    echo "Applying comprehensive patches..."
    
    # Method 1: Classic patches
    sed -i \
        -e "/data\.status.*{/{s/\!//;s/active/NoMoreNagging/}" \
        -e "s/res === null || res === undefined || \!res/true/g" \
        -e "s/res\.data\.status\.toLowerCase() !== 'active'/false/g" \
        -e "s/data\.status !== 'active'/false/g" \
        "$PROXMOXLIB" 2>/dev/null || true
    
    # Method 2: PBS v4 specific
    sed -i "s/\.toLowerCase() !== 'active'/=== 'NoMoreNagging'/g" "$PROXMOXLIB" 2>/dev/null || true
    
    # Method 3: Replace subscription messages
    sed -i "s/No valid subscription/Subscription OK/g" "$PROXMOXLIB" 2>/dev/null || true
    
    # Method 4: Disable popup
    sed -i "s/Ext\.Msg\.show/void(0);\/\/Ext.Msg.show/g" "$PROXMOXLIB" 2>/dev/null || true
    
    # Also patch PBS-specific files
    echo "Checking for PBS-specific GUI files..."
    for file in /usr/share/pbs-www/*.js /usr/share/javascript/proxmox-backup/*.js; do
        if [ -f "$file" ]; then
            echo "Patching $(basename $file)..."
            sed -i \
                -e "s/No valid subscription/Subscription OK/g" \
                -e "s/\.toLowerCase() !== 'active'/=== 'NoMoreNagging'/g" \
                -e "s/data\.status !== 'active'/false/g" \
                "$file" 2>/dev/null || true
        fi
    done
    
    # Verification
    echo "Verification:"
    if grep -q "NoMoreNagging" "$PROXMOXLIB"; then
        echo "✓ NoMoreNagging marker found"
    else
        echo "✗ WARNING: NoMoreNagging marker NOT found"
    fi
    
    if grep -q "No valid subscription" "$PROXMOXLIB"; then
        echo "✗ WARNING: 'No valid subscription' text still present"
    else
        echo "✓ 'No valid subscription' text removed"
    fi
    
    # Create apt hook to maintain patches after updates
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99-no-subscription-nag << 'EOF'
DPkg::Post-Invoke {
    "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then \
        sed -i '/data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
        sed -i 's/\.toLowerCase() !== '\''active'\''/=== '\''NoMoreNagging'\''/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
        sed -i 's/No valid subscription/Subscription OK/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
        sed -i 's/Ext\.Msg\.show/void(0);\/\/Ext.Msg.show/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
    fi";
};
EOF
    
    # Create marker file
    touch /var/lib/proxmox-backup/.subscription-nag-disabled
    
    # Try to reload PBS proxy if it's running
    if pgrep proxmox-backup-proxy > /dev/null 2>&1; then
        echo "Sending SIGHUP to PBS proxy to reload..."
        pkill -HUP proxmox-backup-proxy || true
    fi
fi

echo "PBS post-install configuration completed successfully"
exit 0