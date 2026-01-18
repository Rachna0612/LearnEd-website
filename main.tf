##########################################
# Travel Website (Frontend)
##########################################

##########################################
# Security Group for Both EC2 Instances
##########################################
resource "aws_security_group" "LearnEd_sg" {
  name        = "LearnEd_sg"
  description = "Allow SSH, HTTP, and Nagios access"

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow Nagios Web UI (port 8080)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "LearnEd Security Group"
  }
}


##########################################
# LearnEd Web Server (Frontend) - an education website
##########################################
resource "aws_instance" "LearnEd_instance" {
  ami             = data.aws_ami.amazon_linux.id
  instance_type   = var.instance_type
  key_name        = var.key_name
  security_groups = [aws_security_group.LearnEd_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo amazon-linux-extras install nginx1 -y
              sudo systemctl enable nginx
              sudo systemctl start nginx

              # Install Git
              sudo yum install -y git

              # Clone travel_devops project from GitHub
              cd /tmp
              git clone 
              
              # Copy website files to Nginx web root
              sudo rm -f /usr/share/nginx/html/index.html || true
              sudo cp -r travel_devops/travel_dev/* /usr/share/nginx/html/

              # Restart Nginx
              sudo systemctl restart nginx
              EOF

  tags = {
    Name = "Learn-ed"
  }
}

##########################################
# Nagios Monitoring Server (Backend)
##########################################
resource "aws_instance" "nagios_instance" {
  ami             = data.aws_ami.amazon_linux.id
  instance_type   = var.instance_type
  key_name        = var.key_name
  security_groups = [aws_security_group.LearnEd_sg.name]
  depends_on      = [aws_instance.LearnEd_instance]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd php gcc glibc glibc-common wget unzip httpd-tools gd gd-devel openssl-devel make gettext autoconf net-snmp net-snmp-utils epel-release perl-Net-SNMP

              sudo useradd -m nagios
              sudo groupadd nagcmd
              sudo usermod -a -G nagcmd nagios
              sudo usermod -a -G nagcmd apache

              cd /tmp
              wget -q https://assets.nagios.com/downloads/nagioscore/releases/nagios-4.4.10.tar.gz
              tar -xzf nagios-4.4.10.tar.gz
              cd nagios-4.4.10
              ./configure --with-command-group=nagcmd --with-httpd-conf=/etc/httpd/conf.d
              make all
              sudo make install
              sudo make install-init
              sudo make install-config
              sudo make install-commandmode
              sudo make install-webconf

              cd /tmp
              wget -q https://nagios-plugins.org/download/nagios-plugins-2.3.3.tar.gz
              tar -xzf nagios-plugins-2.3.3.tar.gz
              cd nagios-plugins-2.3.3
              ./configure --with-nagios-user=nagios --with-nagios-group=nagios
              make
              sudo make install

              sudo htpasswd -cb /usr/local/nagios/etc/htpasswd.users nagiosadmin nagios123

              # Wait for LearnEd instance to be ready
              echo "Waiting for LearnEd instance to be ready..."
              sleep 90

              # LearnEd instance IP (injected from Terraform)
              LEARNED_IP="${aws_instance.LearnEd_instance.private_ip}"
              
              # If private IP is not available, use public IP as fallback
              if [ -z "$LEARNED_IP" ] || [ "$LEARNED_IP" == "" ]; then
                LEARNED_IP="${aws_instance.LearnEd_instance.public_ip}"
              fi
              
              echo "Configuring Nagios to monitor LearnEd website at IP: $LEARNED_IP"

              # Ensure objects directory exists and has correct permissions
              sudo mkdir -p /usr/local/nagios/etc/objects
              sudo chown -R nagios:nagios /usr/local/nagios/etc/objects

              # Create Nagios host definition for Travel website
              # Use a simpler approach without template dependencies
              sudo tee /usr/local/nagios/etc/objects/learned_host.cfg > /dev/null <<NAGIOS_HOST
define host {
    host_name               learned-website
    alias                   learned Website
    address                 $LEARNED_IP
    check_command           check-host-alive
    check_interval          5
    retry_interval          1
    max_check_attempts      3
    check_period            24x7
    notification_interval   30
    notification_period     24x7
    notifications_enabled   1
    contact_groups          +admins
}

define service {
    host_name               learned-website
    service_description     learnedl Website HTTP Check
    check_command           check_http
    check_interval          5
    retry_interval          1
    max_check_attempts      3
    check_period            24x7
    notification_interval   30
    notification_period     24x7
    notifications_enabled   1
    contact_groups          +admins
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
    contact_groups          +admins
}
NAGIOS_HOST

              # Set proper permissions
              sudo chown nagios:nagios /usr/local/nagios/etc/objects/learned_host.cfg
              sudo chmod 644 /usr/local/nagios/etc/objects/learned_host.cfg

              # Update nagios.cfg to include the new host definition
              if ! grep -q "learned_host.cfg" /usr/local/nagios/etc/nagios.cfg; then
                echo "cfg_file=/usr/local/nagios/etc/objects/learned_host.cfg" | sudo tee -a /usr/local/nagios/etc/nagios.cfg
              fi

              # Verify the IP was set correctly
              echo "LearnEd IP configured: $LEARNED_IP"
              if [ -z "$LEARNED_IP" ] || [ "$LEARNED_IP" == "" ]; then
                echo "ERROR: LearnEd IP is empty! Cannot configure Nagios."
                exit 1
              fi


              sudo systemctl enable httpd
              sudo systemctl start httpd

              sudo tee /etc/systemd/system/nagios.service > /dev/null <<'SERVICE'
[Unit]
Description=Nagios
After=network.target

[Service]
Type=simple
User=nagios
Group=nagios
ExecStart=/usr/local/nagios/bin/nagios /usr/local/nagios/etc/nagios.cfg
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

              sudo systemctl daemon-reload
              sudo systemctl enable nagios
              
              # Wait a moment for file system to settle
              sleep 5
              
              # Verify Nagios configuration before starting
              echo "Verifying Nagios configuration..."
              CONFIG_CHECK=$(sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg 2>&1)
              CONFIG_STATUS=$?
              
              if [ $CONFIG_STATUS -ne 0 ]; then
                echo "Nagios configuration errors found:"
                echo "$CONFIG_CHECK"
                echo "Attempting to fix common issues..."
                
                # Try to fix missing contact groups by ensuring contacts.cfg exists
                if [ ! -f /usr/local/nagios/etc/objects/contacts.cfg ]; then
                  echo "Creating basic contacts.cfg..."
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
                fi
                
                # Verify again
                sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
              else
                echo "Nagios configuration is valid!"
              fi
              
              # Start Nagios
              sudo systemctl start nagios
              
              # Check if Nagios started successfully
              sleep 3
              if sudo systemctl is-active --quiet nagios; then
                echo "Nagios started successfully!"
              else
                echo "Nagios failed to start. Checking logs..."
                sudo journalctl -u nagios -n 50 --no-pager
              fi
              EOF

  tags = {
    Name = "Nagios-Monitor"
  }
}
