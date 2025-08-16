#!/bin/bash
# Don't use set -e because arithmetic operations can return non-zero

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
    
    if [ -f "$PROXMOXLIB" ]; then
        # Create original backup if not exists
        if [ ! -f "${PROXMOXLIB}.original" ]; then
            cp "$PROXMOXLIB" "${PROXMOXLIB}.original"
            echo "Created original backup: ${PROXMOXLIB}.original"
        fi
        
        echo "Applying subscription nag patches..."
        
        # Pattern 1: Fix the actual subscription check
        sed -i "s/res\.data\.status\.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'NoMoreNagging'/g" "$PROXMOXLIB"
        echo "✓ Patched subscription status check"
        
        # Pattern 2: Change the "No valid subscription" message
        sed -i "s/No valid subscription/Subscription OK/g" "$PROXMOXLIB"
        echo "✓ Patched subscription message"
        
        # Pattern 3: Alternative check pattern
        sed -i "s/data\.status !== 'active'/data.status === 'NoMoreNagging'/g" "$PROXMOXLIB"
        echo "✓ Patched alternative status check"
        
        # Pattern 4: Double-quote variant
        sed -i 's/data\.status\.toLowerCase() !== "active"/data.status.toLowerCase() === "NoMoreNagging"/g' "$PROXMOXLIB"
        echo "✓ Patched double-quote variant"
        
        # Verification
        echo ""
        echo "Verification Results:"
        if grep -q "NoMoreNagging" "$PROXMOXLIB"; then
            echo "✓ NoMoreNagging marker found - patch successful!"
        else
            echo "⚠ NoMoreNagging marker not found"
        fi
        
        if grep -q "No valid subscription" "$PROXMOXLIB"; then
            echo "⚠ Warning: 'No valid subscription' text still present"
        else
            echo "✓ 'No valid subscription' text successfully removed"
        fi
    else
        echo "ERROR: proxmoxlib.js not found"
        exit 1
    fi
    
    # Create marker file
    mkdir -p /var/lib/proxmox-backup
    touch /var/lib/proxmox-backup/.subscription-nag-disabled
fi

echo "Signaling PBS proxy to reload..."
pkill -HUP -f proxmox-backup-proxy 2>/dev/null || true

echo "PBS post-install configuration completed successfully!"
echo "NOTE: Clear your browser cache (Ctrl+F5) to see changes!"
exit 0