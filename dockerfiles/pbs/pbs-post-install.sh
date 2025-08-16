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

# DO NOT create subscription file - PBS handles missing file better
# Just ensure the directory exists
mkdir -p /etc/proxmox-backup

# Remove any existing subscription file
rm -f /etc/proxmox-backup/subscription

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
        # Create backup
        if [ ! -f "${PROXMOXLIB}.original" ]; then
            cp "$PROXMOXLIB" "${PROXMOXLIB}.original"
        fi
        
        # Apply patches
        if ! grep -q "NoMoreNagging" "$PROXMOXLIB" 2>/dev/null; then
            echo "Applying subscription nag patch..."
            
            sed -i.bak \
                -e "/data\.status.*{/{s/\!//;s/active/NoMoreNagging/}" \
                -e "s/res === null || res === undefined || \!res || res\.data\.status\.toLowerCase() !== 'active'/false/" \
                -e "s/could not read subscription status/subscription OK/g" \
                -e "s/error decoding base64 data/subscription active/g" \
                "$PROXMOXLIB" 2>/dev/null || true
            
            echo "Patch applied"
        else
            echo "Already patched"
        fi
    else
        echo "Warning: proxmoxlib.js not found"
    fi
    
    # Create apt hook to maintain patch after updates
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99-no-subscription-nag << 'EOF'
DPkg::Post-Invoke {
    "rm -f /etc/proxmox-backup/subscription 2>/dev/null || true";
    "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ] && ! grep -q 'NoMoreNagging' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; then sed -i -e '/data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' -e 's/could not read subscription status/subscription OK/g' -e 's/error decoding base64 data/subscription active/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; fi";
};
EOF
    
    # Create marker file
    touch /var/lib/proxmox-backup/.subscription-nag-disabled
fi

echo "PBS post-install configuration completed"
echo ""
echo "IMPORTANT: Clear your browser cache (Ctrl+F5) to see changes!"
exit 0