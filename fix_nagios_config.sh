#!/bin/bash
# Script to fix Nagios configuration on the running instance
# Run this script on the Nagios server after SSH access

echo "Fixing Nagios configuration..."

# Get LearnEd instance IP (you may need to update this with actual IP)
# Option 1: If you know the LearnEd instance IP, set it here:
LEARNED_IP="YOUR_LEARNED_INSTANCE_IP_HERE"

# Option 2: Or use AWS CLI to find it (requires IAM role with EC2 permissions)
if command -v aws &> /dev/null; then
    LEARNED_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=LearnEd-Server" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null)
    if [ -z "$LEARNED_IP" ] || [ "$LEARNED_IP" == "None" ]; then
        LEARNED_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=LearnEd-Server" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null)
    fi
fi

if [ -z "$LEARNED_IP" ] || [ "$LEARNED_IP" == "None" ] || [ "$LEARNED_IP" == "YOUR_LEARNED_INSTANCE_IP_HERE" ]; then
    echo "ERROR: Please set LEARNED_IP variable with the LearnEd instance IP address"
    echo "Usage: LEARNED_IP=1.2.3.4 bash fix_nagios_config.sh"
    exit 1
fi

echo "Using LearnEd IP: $LEARNED_IP"

# Ensure objects directory exists
sudo mkdir -p /usr/local/nagios/etc/objects
sudo chown -R nagios:nagios /usr/local/nagios/etc/objects

# Create/update contacts.cfg if it doesn't exist
if [ ! -f /usr/local/nagios/etc/objects/contacts.cfg ]; then
    echo "Creating contacts.cfg..."
    sudo tee /usr/local/nagios/etc/objects/contacts.cfg > /dev/null <<CONTACTS
define contact {
    contact_name                    nagiosadmin
    alias                           Nagios Admin
    service_notification_period     24x7
    host_notification_period        24x7
    service_notification_options    w,u,c,r
    host_notification_options       d,u,r
    service_notification_commands   notify-service-by-email
    host_notification_commands      notify-host-by-email
    email                           nagios@localhost
}

define contactgroup {
    contactgroup_name       admins
    alias                   Nagios Administrators
    members                 nagiosadmin
}
CONTACTS
    sudo chown nagios:nagios /usr/local/nagios/etc/objects/contacts.cfg
    
    # Add contacts.cfg to nagios.cfg if not already there
    if ! grep -q "contacts.cfg" /usr/local/nagios/etc/nagios.cfg; then
        echo "cfg_file=/usr/local/nagios/etc/objects/contacts.cfg" | sudo tee -a /usr/local/nagios/etc/nagios.cfg
    fi
fi

# Create/update learned_host.cfg
echo "Creating learned_host.cfg..."
sudo tee /usr/local/nagios/etc/objects/learned_host.cfg > /dev/null <<NAGIOS_HOST
define host {
    host_name               learned-website
    alias                   LearnEd Website - an education website
    address                 $LEARNED_IP
    check_command           check-host-alive
    check_interval          5
    retry_interval          1
    max_check_attempts      3
    check_period            24x7
    notification_interval   30
    notification_period     24x7
    notifications_enabled   1
    contact_groups          admins
}

define service {
    host_name               learned-website
    service_description     LearnEd Website HTTP Check
    check_command           check_http
    check_interval          5
    retry_interval          1
    max_check_attempts      3
    check_period            24x7
    notification_interval   30
    notification_period     24x7
    notifications_enabled   1
    contact_groups          admins
}

define service {
    host_name               learned-website
    service_description     LearnEd Website Ping
    check_command           check_ping!100.0,20%!500.0,60%
    check_interval          5
    retry_interval          1
    max_check_attempts      3
    check_period            24x7
    notification_interval   30
    notification_period     24x7
    notifications_enabled   1
    contact_groups          admins
}
NAGIOS_HOST

# Set proper permissions
sudo chown nagios:nagios /usr/local/nagios/etc/objects/learned_host.cfg
sudo chmod 644 /usr/local/nagios/etc/objects/learned_host.cfg

# Add learned_host.cfg to nagios.cfg if not already there
if ! grep -q "learned_host.cfg" /usr/local/nagios/etc/nagios.cfg; then
    echo "cfg_file=/usr/local/nagios/etc/objects/learned_host.cfg" | sudo tee -a /usr/local/nagios/etc/nagios.cfg
fi

# Verify configuration
echo "Verifying Nagios configuration..."
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

if [ $? -eq 0 ]; then
    echo "Configuration is valid! Reloading Nagios..."
    sudo systemctl reload nagios
    echo "Nagios has been reloaded. Please check the web interface."
else
    echo "Configuration has errors. Please review the output above."
    exit 1
fi

