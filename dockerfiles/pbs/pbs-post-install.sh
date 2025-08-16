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
    
    # Wait for the file to exist (max 30 seconds)
    for i in $(seq 1 30); do
        if [ -f "$PROXMOXLIB" ]; then
            echo "Found proxmoxlib.js"
            break
        fi
        sleep 1
    done
    
    if [ -f "$PROXMOXLIB" ]; then
        # Create original backup if not exists
        if [ ! -f "${PROXMOXLIB}.original" ]; then
            cp "$PROXMOXLIB" "${PROXMOXLIB}.original"
            echo "Created original backup: ${PROXMOXLIB}.original"
        fi
        
        # METHOD 1: Original patching method
        echo "Applying Method 1: Original patch..."
        
        # Apply multiple patterns from the original method
        sed -i.method1 \
            -e "/data\.status.*{/{s/\!//;s/active/NoMoreNagging/}" \
            -e "s/res === null || res === undefined || \!res/true/g" \
            -e "s/res\.data\.status\.toLowerCase() !== 'active'/false/g" \
            -e "s/data\.status !== 'active'/false/g" \
            -e "s/Ext\.Msg\.show/void(0);\/\/Ext.Msg.show/g" \
            "$PROXMOXLIB" 2>/dev/null || true
        
        echo "Method 1 applied"
        
        # METHOD 2: Bloodpack's method for PBS v4
        echo "Applying Method 2: Bloodpack's PBS v4 patch..."
        
        # Script to remove the Proxmox Backup Server no subscription nag.
        # Copyright (c) 2025 Bloodpack
        # Author: Bloodpack 
        # License: MIT license
        # https://github.com/Bloodpack/proxmox_nag_removal.git
        # VERSION: 2.00 from 08.08.2025
        
        BACKUP_DIR="/usr/share/javascript/proxmox-widget-toolkit"
        TIMESTAMP=$(date +%Y%m%d%H%M%S)
        BACKUP_FILE="${BACKUP_DIR}/proxmoxlib.js.bak.${TIMESTAMP}"
        
        # Backup current state
        cp "$PROXMOXLIB" "$BACKUP_FILE"
        echo "[no-nag] Backup created: $BACKUP_FILE"
        
        # Rotate backups, keep only last 3
        BACKUPS=($(ls -1t ${BACKUP_DIR}/proxmoxlib.js.bak.* 2>/dev/null))
        NUM_BACKUPS=${#BACKUPS[@]}
        if [ "$NUM_BACKUPS" -gt 3 ]; then
            for ((i=3; i<NUM_BACKUPS; i++)); do
                rm -f "${BACKUPS[$i]}"
                echo "[no-nag] Removed old backup: ${BACKUPS[$i]}"
            done
        fi
        
        # Apply Bloodpack's patch for PBS v4
        sed -i "s/\.toLowerCase() !== 'active'/=== 'NoMoreNagging'/g" "$PROXMOXLIB"
        
        echo "Method 2 applied"
        
        # Additional cleanup patterns - catch any remaining subscription checks
        echo "Applying additional cleanup patterns..."
        
        # Remove any "No valid subscription" messages
        sed -i "s/No valid subscription/Subscription OK/g" "$PROXMOXLIB" 2>/dev/null || true
        
        # Patch any remaining subscription status checks
        sed -i "s/'active'/true/g" "$PROXMOXLIB" 2>/dev/null || true
        
        # Final verification
        if grep -q "NoMoreNagging" "$PROXMOXLIB"; then
            echo "✓ All patches applied successfully - subscription nag removed"
        else
            echo "⚠ Warning: NoMoreNagging marker not found, but patches were applied"
        fi
    else
        echo "Warning: proxmoxlib.js not found"
    fi
    
    # Also check and patch PBS-specific files
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
    
    # Create apt hook to maintain ALL patches after updates
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99-no-subscription-nag << 'EOF'
DPkg::Post-Invoke {
    "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then \
        # Apply both methods \
        sed -i '/data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
        sed -i 's/\.toLowerCase() !== '\''active'\''/=== '\''NoMoreNagging'\''/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
        sed -i 's/No valid subscription/Subscription OK/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
    fi";
};
EOF
    
    # Create marker file
    touch /var/lib/proxmox-backup/.subscription-nag-disabled
fi

# Restart PBS proxy if it's running to apply changes
if systemctl is-enabled proxmox-backup-proxy >/dev/null 2>&1; then
    echo "Restarting PBS proxy to apply changes..."
    systemctl restart proxmox-backup-proxy || true
fi

echo "PBS post-install configuration completed successfully"
exit 0