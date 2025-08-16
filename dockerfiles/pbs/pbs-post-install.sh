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

# Remove subscription file to prevent base64 errors
echo "Removing subscription file..."
rm -f /etc/proxmox-backup/subscription
mkdir -p /etc/proxmox-backup

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
    
    JS_FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    BACKUP_DIR="/usr/share/javascript/proxmox-widget-toolkit"
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_FILE="${BACKUP_DIR}/proxmoxlib.js.bak.${TIMESTAMP}"
    
    # Wait for the file to exist
    for i in $(seq 1 30); do
        if [ -f "$JS_FILE" ]; then
            echo "Found proxmoxlib.js"
            break
        fi
        sleep 1
    done
    
    if [ -f "$JS_FILE" ]; then
        # Check if already patched
        if grep -q "NoMoreNagging" "$JS_FILE"; then
            echo "Already patched."
        else
            # Backup original
            cp "$JS_FILE" "$BACKUP_FILE"
            echo "Backup created: $BACKUP_FILE"
            
            # Rotate backups, keep only last 3
            BACKUPS=($(ls -1t ${BACKUP_DIR}/proxmoxlib.js.bak.* 2>/dev/null))
            NUM_BACKUPS=${#BACKUPS[@]}
            if [ "$NUM_BACKUPS" -gt 3 ]; then
                for ((i=3; i<NUM_BACKUPS; i++)); do
                    rm -f "${BACKUPS[$i]}"
                    echo "Removed old backup: ${BACKUPS[$i]}"
                done
            fi
            
            # Apply patch for PBS v4 (the exact method from the script you provided)
            sed -i "s/\.toLowerCase() !== 'active'/=== 'NoMoreNagging'/g" "$JS_FILE"
            
            # Also apply additional patches to handle all cases
            sed -i "s/Ext.Msg.show({/void({ \/\//g" "$JS_FILE"
            sed -i 's/No valid subscription/Subscription OK/g' "$JS_FILE"
            sed -i 's/could not read subscription status//g' "$JS_FILE"
            sed -i 's/error decoding base64 data//g' "$JS_FILE"
            
            # Confirm patch
            if grep -q "NoMoreNagging" "$JS_FILE"; then
                echo "Patch applied successfully."
            else
                echo "Patch failed, restoring backup..."
                cp "$BACKUP_FILE" "$JS_FILE"
                exit 1
            fi
        fi
    else
        echo "Warning: proxmoxlib.js not found"
    fi
    
    # Create APT hook for persistence (using the new patch method)
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99-pbs-no-nag << 'EOF'
DPkg::Post-Invoke {
    "rm -f /etc/proxmox-backup/subscription 2>/dev/null || true";
    "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ] && ! grep -q 'NoMoreNagging' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; then sed -i \"s/\.toLowerCase() !== 'active'/=== 'NoMoreNagging'/g\" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null; fi";
};
EOF
    
    touch /var/lib/proxmox-backup/.subscription-nag-disabled
fi

echo "PBS post-install configuration completed"
echo ""
echo "IMPORTANT: Clear your browser cache!"
echo "  - Press Ctrl+Shift+Delete"
echo "  - Select 'Cached images and files'"
echo "  - Clear data"
echo "  - Or use incognito/private window"
exit 0