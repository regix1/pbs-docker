#!/usr/bin/env bash

# Container-optimized PBS subscription nag removal script
# Removes subscription warnings from Proxmox Backup Server

set -e

# Environment variables with defaults
PBS_ENTERPRISE=${PBS_ENTERPRISE:-"yes"}
PBS_NO_SUBSCRIPTION=${PBS_NO_SUBSCRIPTION:-"yes"}
DISABLE_SUBSCRIPTION_NAG=${DISABLE_SUBSCRIPTION_NAG:-"yes"}

echo "PBS Post-Install Configuration:"
echo "  PBS_ENTERPRISE=${PBS_ENTERPRISE}"
echo "  PBS_NO_SUBSCRIPTION=${PBS_NO_SUBSCRIPTION}"
echo "  DISABLE_SUBSCRIPTION_NAG=${DISABLE_SUBSCRIPTION_NAG}"

VERSION="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"

# Configure repositories
if [[ "${PBS_ENTERPRISE}" == "yes" ]]; then
    echo "Disabling enterprise repository..."
    echo "# Disabled by pbs-post-install.sh" > /etc/apt/sources.list.d/pbs-enterprise.list
fi

if [[ "${PBS_NO_SUBSCRIPTION}" == "yes" ]]; then
    echo "Enabling no-subscription repository..."
    echo "deb http://download.proxmox.com/debian/pbs ${VERSION} pbs-no-subscription" > /etc/apt/sources.list.d/pbs-install-repo.list
fi

# Disable subscription nag in the UI
if [[ "${DISABLE_SUBSCRIPTION_NAG}" == "yes" ]]; then
    echo "Disabling subscription nag in UI..."

    # Wait for PBS to start and create the file (up to 120 seconds)
    for i in {1..60}; do
        if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then
            echo "Found proxmoxlib.js, applying patch..."

            # Check if already patched
            if ! grep -q "NoMoreNagging" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; then
                # Create backup
                cp /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js \
                   /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak

                # Apply the patch
                sed -i "s/Ext.Msg.show/void\(0\)\;\/\/Ext.Msg.show/g" \
                    /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
                    
                sed -i "/data.status.*{/{s/\!//;s/active/NoMoreNagging/}" \
                    /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
                    
                echo "Subscription nag patch applied successfully"
            else
                echo "Subscription nag already patched"
            fi
            break
        fi
        echo "Waiting for proxmoxlib.js... (attempt $i/60)"
        sleep 2
    done

    # Also patch the PBS-specific subscription check
    if [ -f /usr/share/javascript/proxmox-backup/js/proxmox-backup-gui.js ]; then
        echo "Patching PBS GUI subscription check..."
        sed -i "s/Ext.Msg.show/void\(0\)\;\/\/Ext.Msg.show/g" \
            /usr/share/javascript/proxmox-backup/js/proxmox-backup-gui.js 2>/dev/null || true
    fi

    # Create apt configuration to handle future updates
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99-no-nag-script << 'INNER_EOF'
DPkg::Post-Invoke {
    "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then
        grep -q 'NoMoreNagging' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js || \
        sed -i '/data.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true;
    fi";
    "if [ -f /usr/share/javascript/proxmox-backup/js/proxmox-backup-gui.js ]; then
        sed -i 's/Ext.Msg.show/void(0);\/\/Ext.Msg.show/g' /usr/share/javascript/proxmox-backup/js/proxmox-backup-gui.js 2>/dev/null || true;
    fi";
};
INNER_EOF
fi

echo "PBS post-install configuration completed successfully"
touch /var/lib/proxmox-backup/.subscription-nag-disabled

exit 0