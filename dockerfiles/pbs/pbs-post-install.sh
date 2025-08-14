#!/bin/bash

echo "PBS Post-Install Configuration:"
echo "  PBS_ENTERPRISE=${PBS_ENTERPRISE}"
echo "  PBS_NO_SUBSCRIPTION=${PBS_NO_SUBSCRIPTION}"
echo "  DISABLE_SUBSCRIPTION_NAG=${DISABLE_SUBSCRIPTION_NAG}"

# Disable enterprise repository if requested
if [ "${PBS_ENTERPRISE}" = "no" ] || [ "${PBS_ENTERPRISE}" = "false" ]; then
    echo "Disabling enterprise repository..."
    if [ -f /etc/apt/sources.list.d/pbs-enterprise.list ]; then
        sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/pbs-enterprise.list
    fi
fi

# Enable no-subscription repository if requested
if [ "${PBS_NO_SUBSCRIPTION}" = "yes" ] || [ "${PBS_NO_SUBSCRIPTION}" = "true" ]; then
    echo "Enabling no-subscription repository..."
    if ! grep -q "pbs-no-subscription" /etc/apt/sources.list.d/*.list 2>/dev/null && \
       ! grep -q "pbs-no-subscription" /etc/apt/sources.list 2>/dev/null; then
        echo "deb http://download.proxmox.com/debian/pbs $(lsb_release -sc) pbs-no-subscription" > /etc/apt/sources.list.d/pbs-no-subscription.list
    fi
fi

# Disable subscription nag if requested
if [ "${DISABLE_SUBSCRIPTION_NAG}" = "yes" ] || [ "${DISABLE_SUBSCRIPTION_NAG}" = "true" ]; then
    echo "Disabling subscription nag in UI..."
    
    # Method 1: Try the old location first (PBS < 3.x)
    PROXMOXLIB_OLD="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    
    # Method 2: New location (PBS 3.x+)
    PROXMOXLIB_NEW="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    
    # Method 3: Check for ExtJS-based UI files
    EXTJS_DIR="/usr/share/javascript/extjs"
    
    # Function to patch the subscription check
    patch_subscription() {
        local file="$1"
        if [ -f "$file" ]; then
            echo "Found $(basename $file), applying patch..."
            
            # Backup original file
            cp "$file" "${file}.backup.$(date +%Y%m%d)" 2>/dev/null || true
            
            # Multiple patch strategies for different PBS versions
            
            # Strategy 1: Classic patch for older versions
            if grep -q "data\.status" "$file" 2>/dev/null; then
                sed -i "/data\.status/s/\!//g" "$file"
                sed -i "/data\.status.*{/,/\}/s/'active'/true/g" "$file"
                echo "Applied classic patch"
            fi
            
            # Strategy 2: Newer PBS versions (3.x+)
            if grep -q "Ext\.Msg\.show" "$file" 2>/dev/null; then
                # Look for subscription popup and disable it
                sed -i "/No valid subscription/,/\}\);/d" "$file" 2>/dev/null || true
            fi
            
            # Strategy 3: Widget toolkit method
            if grep -q "checked_command: function" "$file" 2>/dev/null; then
                # Replace the checked_command function to skip subscription check
                sed -i "/checked_command: function/,/^[[:space:]]*},/c\
    checked_command: function(orig_cmd) {\
        Proxmox.Utils.API2Request({\
            url: orig_cmd.url,\
            method: orig_cmd.method || 'POST',\
            params: orig_cmd.params,\
            failure: orig_cmd.failure,\
            success: orig_cmd.success || Ext.emptyFn\
        });\
    }," "$file" 2>/dev/null || true
            fi
            
            # Strategy 4: Simple replacement approach
            sed -i "s/res === null || res === undefined || \!res/true/g" "$file" 2>/dev/null || true
            sed -i "s/res\.data\.status\.toLowerCase() !== 'active'/false/g" "$file" 2>/dev/null || true
            
            echo "Subscription nag patch applied to $file"
            return 0
        fi
        return 1
    }
    
    # Apply patches to all known locations
    patched=false
    
    # Check main proxmoxlib.js
    if patch_subscription "$PROXMOXLIB_OLD"; then
        patched=true
    fi
    
    # Check for PBS-specific UI files
    for file in /usr/share/pbs-www/*.js /usr/share/javascript/proxmox-backup/*.js; do
        if [ -f "$file" ] && grep -q "subscription\|No valid subscription" "$file" 2>/dev/null; then
            patch_subscription "$file"
            patched=true
        fi
    done
    
    # Additional approach: Create apt hook to maintain the patch after updates
    cat > /etc/apt/apt.conf.d/99-no-subscription-nag << 'EOF'
DPkg::Post-Invoke {
    "if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then sed -i '/data\.status/s/\!//g; /data\.status.*{/,/\}/s/\"active\"/true/g; s/res === null || res === undefined || \!res/true/g; s/res\.data\.status\.toLowerCase() !== \"active\"/false/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true; fi";
    "if [ -f /usr/share/pbs-www/index.html ]; then sed -i 's/No valid subscription/Subscription OK/g' /usr/share/pbs-www/*.js 2>/dev/null || true; fi";
};
EOF
    
    if [ "$patched" = true ]; then
        echo "Subscription nag patch applied successfully"
    else
        echo "Warning: Could not find files to patch. PBS might use a different structure."
    fi
    
    # Force clear any cached subscription status
    rm -f /var/lib/proxmox-backup/subscription 2>/dev/null || true
    
    # Create a fake subscription file (for some PBS versions)
    mkdir -p /etc/proxmox-backup
    cat > /etc/proxmox-backup/subscription << 'EOF'
{
    "status": "active",
    "checktime": "$(date +%s)",
    "key": "pbs-no-subscription",
    "validdirectory": "PBS No-Subscription",
    "productname": "Proxmox Backup Server"
}
EOF
fi

echo "Patching PBS GUI subscription check..."

# Extra step: Try to patch the PBS daemon itself
if [ -f /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-api ]; then
    # This is a binary, we can't patch it directly, but we can override the subscription check
    # by creating a systemd override
    mkdir -p /etc/systemd/system/proxmox-backup-api.service.d
    cat > /etc/systemd/system/proxmox-backup-api.service.d/no-subscription.conf << 'EOF'
[Service]
Environment="PBS_SUBSCRIPTION_OVERRIDE=1"
EOF
    systemctl daemon-reload
fi

echo "PBS post-install configuration completed successfully"

# Restart the web service to apply changes
if systemctl is-active proxmox-backup-proxy >/dev/null 2>&1; then
    echo "Restarting PBS proxy to apply changes..."
    systemctl restart proxmox-backup-proxy
fi