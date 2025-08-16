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
        
        # Pattern 1: Fix the actual subscription check
        if grep -q "res\.data\.status\.toLowerCase() !== 'active'" "$PROXMOXLIB"; then
            sed -i "s/res\.data\.status\.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'NoMoreNagging'/g" "$PROXMOXLIB"
            echo "✓ Patched subscription status check"
            CHANGES=$((CHANGES + 1))
        fi
        
        # Pattern 2: Change the "No valid subscription" message
        if grep -q "No valid subscription" "$PROXMOXLIB"; then
            sed -i "s/No valid subscription/Subscription OK/g" "$PROXMOXLIB"
            echo "✓ Patched subscription message"
            CHANGES=$((CHANGES + 1))
        fi
        
        # Pattern 3: Alternative check pattern (some versions)
        if grep -q "data\.status !== 'active'" "$PROXMOXLIB"; then
            sed -i "s/data\.status !== 'active'/data.status === 'NoMoreNagging'/g" "$PROXMOXLIB"
            echo "✓ Patched alternative status check"
            CHANGES=$((CHANGES + 1))
        fi
        
        # Pattern 4: Another variant with double quotes
        if grep -q 'data\.status\.toLowerCase() !== "active"' "$PROXMOXLIB"; then
            sed -i 's/data\.status\.toLowerCase() !== "active"/data.status.toLowerCase() === "NoMoreNagging"/g' "$PROXMOXLIB"
            echo "✓ Patched double-quote variant"
            CHANGES=$((CHANGES + 1))
        fi
        
        # Pattern 5: Handle the Ext.Msg.show popup
        if grep -q "Ext\.Msg\.show" "$PROXMOXLIB"; then
            # Comment out the popup but preserve the line
            sed -i 's/^\(\s*\)Ext\.Msg\.show/\1\/\/Ext.Msg.show/g' "$PROXMOXLIB"
            echo "✓ Disabled popup messages"
            CHANGES=$((CHANGES + 1))
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
        echo "Changed patterns (first 5 matches):"
        grep -n "NoMoreNagging\|Subscription OK" "$PROXMOXLIB" 2>/dev/null | head -5 || echo "No patterns found"
        
    else
        echo "ERROR: proxmoxlib.js not found at $PROXMOXLIB"
        exit 1
    fi
    
    # Also patch PBS-specific files
    echo ""
    echo "Checking for PBS-specific GUI files..."
    for dir in /usr/share/pbs-www /usr/share/javascript/proxmox-backup; do
        if [ -d "$dir" ]; then
            for file in "$dir"/*.js; do
                if [ -f "$file" ]; then
                    if grep -q "No valid subscription\|data\.status.*active" "$file" 2>/dev/null; then
                        echo "Patching $(basename $file)..."
                        sed -i \
                            -e "s/No valid subscription/Subscription OK/g" \
                            -e "s/\.toLowerCase() !== 'active'/=== 'NoMoreNagging'/g" \
                            -e "s/data\.status !== 'active'/data.status === 'NoMoreNagging'/g" \
                            "$file" 2>/dev/null || true
                    fi
                fi
            done
        fi
    done
    
    # Create apt hook to maintain patches after updates
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99-no-subscription-nag << 'EOF'
DPkg::Post-Invoke {
    "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then \
        sed -i \"s/res\.data\.status\.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'NoMoreNagging'/g\" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
        sed -i 's/No valid subscription/Subscription OK/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
        sed -i 's/data\.status !== .active./data.status === .NoMoreNagging./g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; \
    fi";
};
EOF
    
    # Create marker file
    mkdir -p /var/lib/proxmox-backup
    touch /var/lib/proxmox-backup/.subscription-nag-disabled
    echo "Created marker file"
fi

# Try to signal PBS proxy to reload (don't fail if it doesn't work)
echo ""
echo "Signaling PBS proxy to reload..."
if pkill -HUP -f proxmox-backup-proxy 2>/dev/null; then
    echo "PBS proxy signaled successfully"
else
    echo "Could not signal PBS proxy (may not be running yet)"
fi

echo ""
echo "PBS post-install configuration completed successfully!"
echo "NOTE: Clear your browser cache (Ctrl+F5) to see changes!"
exit 0