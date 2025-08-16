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
        
        echo "Applying subscription nag patches..."
        
        # Count changes for verification
        CHANGES=0
        
        # Pattern 1: Fix the actual subscription check (line 615/20604 pattern)
        # Change: res.data.status.toLowerCase() !== 'active'
        # To: res.data.status.toLowerCase() === 'NoMoreNagging'
        if grep -q "res\.data\.status\.toLowerCase() !== 'active'" "$PROXMOXLIB"; then
            sed -i "s/res\.data\.status\.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'NoMoreNagging'/g" "$PROXMOXLIB"
            echo "✓ Patched subscription status check"
            ((CHANGES++))
        fi
        
        # Pattern 2: Change the "No valid subscription" message
        if grep -q "No valid subscription" "$PROXMOXLIB"; then
            sed -i "s/No valid subscription/Subscription OK/g" "$PROXMOXLIB"
            echo "✓ Patched subscription message"
            ((CHANGES++))
        fi
        
        # Pattern 3: Alternative check pattern (some versions)
        if grep -q "data\.status !== 'active'" "$PROXMOXLIB"; then
            sed -i "s/data\.status !== 'active'/data.status === 'NoMoreNagging'/g" "$PROXMOXLIB"
            echo "✓ Patched alternative status check"
            ((CHANGES++))
        fi
        
        # Pattern 4: Another variant
        if grep -q "data\.status\.toLowerCase() !== \"active\"" "$PROXMOXLIB"; then
            sed -i "s/data\.status\.toLowerCase() !== \"active\"/data.status.toLowerCase() === \"NoMoreNagging\"/g" "$PROXMOXLIB"
            echo "✓ Patched double-quote variant"
            ((CHANGES++))
        fi
        
        # Pattern 5: Handle the Ext.Msg.show popup
        if grep -q "Ext\.Msg\.show" "$PROXMOXLIB"; then
            # Comment out the popup but preserve the line
            sed -i "s/^\(\s*\)Ext\.Msg\.show/\1\/\/Ext.Msg.show/g" "$PROXMOXLIB"
            echo "✓ Disabled popup messages"
            ((CHANGES++))
        fi
        
        # Verification
        echo ""
        echo "Verification Results:"
        if grep -q "NoMoreNagging" "$PROXMOXLIB"; then
            echo "✓ NoMoreNagging marker found - patch successful!"
        else
            echo "⚠ NoMoreNagging marker not found, but $CHANGES changes were made"
        fi
        
        if grep -q "No valid subscription" "$PROXMOXLIB"; then
            echo "⚠ Warning: 'No valid subscription' text still present"
        else
            echo "✓ 'No valid subscription' text successfully removed"
        fi
        
        # Show what we changed
        echo ""
        echo "Changed patterns:"
        grep -n "NoMoreNagging\|Subscription OK" "$PROXMOXLIB" | head -5 || true
        
    else
        echo "Warning: proxmoxlib.js not found"
    fi
    
    # Create apt hook to maintain patches after updates
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99-no-subscription-nag << 'EOF'
DPkg::Post-Invoke {
    "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then \
        sed -i \"s/res\.data\.status\.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'NoMoreNagging'/g\" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
        sed -i 's/No valid subscription/Subscription OK/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
    fi";
};
EOF
    
    # Create marker file
    touch /var/lib/proxmox-backup/.subscription-nag-disabled
fi

# Restart PBS proxy if it's running (in container, use pkill)
echo "Signaling PBS proxy to reload..."
pkill -HUP -f proxmox-backup-proxy 2>/dev/null || true

echo "PBS post-install configuration completed successfully"
echo "NOTE: Clear your browser cache (Ctrl+F5) to see changes!"
exit 0