#!/bin/bash

# Variables
SERVICE_NAME="anycast.service"
STATIC_BASE_DIR="/opt/anycast4"  # For static files
RUNTIME_BASE_DIR="/opt/anycast4/var" # For runtime/dynamic files
CONFIG_DIR="/etc/anycast"  # Configuration directory
LOG_DIR="/var/log/anycast" # Log directory
LIB_DIR_SRC="lib"  # Source lib directory
LIB_DIR_DEST="${STATIC_BASE_DIR}/lib"  # Destination lib directory

# Derived paths
SERVICE_FILE_DEST="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_FILE_DEST="${CONFIG_DIR}/config.yml"
DAEMON_SCRIPT_DEST="${STATIC_BASE_DIR}/anycast_daemon.pl"

# Current working directory
CURRENT_DIR="$(pwd)"

# Function to create directories if not present
create_directory() {
  local dir=$1
  if [[ ! -d "$dir" ]]; then
    echo "Creating directory: $dir"
    sudo mkdir -p "$dir"
    sudo chmod 755 "$dir" # Ensure proper permissions
  else
    echo "Directory already exists: $dir"
  fi
}

# Function to copy files
copy_file() {
  local src=$1
  local dest=$2
  if [[ -f "$src" ]]; then
    echo "Copying $src to $dest..."
    sudo cp -f "$src" "$dest"
  else
    echo "File $src not found. Skipping."
  fi
}

# Function to copy a directory recursively
copy_directory() {
  local src=$1
  local dest=$2
  if [[ -d "$src" ]]; then
    echo "Copying directory $src to $dest..."
    sudo cp -r "$src" "$dest"
  else
    echo "Directory $src not found. Skipping."
  fi
}

# Function to create or overwrite a file
create_file() {
  local content=$1
  local dest=$2
  echo "Creating $dest..."
  echo "$content" | sudo tee "$dest" > /dev/null
}

# Create required directories
create_directory "$STATIC_BASE_DIR"
create_directory "$RUNTIME_BASE_DIR"
create_directory "${RUNTIME_BASE_DIR}/dpinger_outputs"
create_directory "$CONFIG_DIR"
create_directory "$LOG_DIR" # Create the log directory

# Copy the `lib` directory
copy_directory "$LIB_DIR_SRC" "$LIB_DIR_DEST"

# Define file contents with `EOL`
read -r -d '' SERVICE_FILE_CONTENT <<EOL
[Unit]
Description=Anycast Perl Daemon Service
After=network.target

[Service]
ExecStart=/usr/bin/perl ${DAEMON_SCRIPT_DEST}
StandardOutput=append:${LOG_DIR}/anycast.log
StandardError=append:${LOG_DIR}/anycast.log
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOL

read -r -d '' CONFIG_FILE_CONTENT <<EOL
static_base_dir: "${STATIC_BASE_DIR}"
runtime_base_dir: "${RUNTIME_BASE_DIR}"
state_file: "{{ runtime_base_dir }}/anycast_status.json"
log_level: "DEBUG"
log_file: "${LOG_DIR}/anycast_daemon.log"
interval: 10

dpinger:
  exec_path: "/usr/local/bin/dpinger"
  bind_address: "0.0.0.0"
  send_interval: 500
  loss_interval: 2000
  time_period: 60000
  report_interval: 1
  output_dir: "{{ runtime_base_dir }}/dpinger_outputs"
  latency_low: 200
  latency_high: 500
  loss_low: 10
  loss_high: 20

xymon:
  server_ip: "172.26.121.11"
  hostname: "anycast_monitor"

controllers:
  - name: "Controller 1"
    service_monitoring:
      name: "Anycast group 1"
      operator: "all"
      type: "group"
      elements:
        - name: "Gateway Group 1"
          type: "group"
          operator: "any"
          elements:
            - name: "gateway1"
              type: "gateway"
              ip: "192.168.1.3"
            - name: "gateway2"
              type: "gateway"
              ip: "8.8.8.8"
        - name: "Service Group 1"
          type: "group"
          operator: "all"
          elements:
            - name: "postfix"
              type: "group"
              operator: "all"
              elements:
                - name: "systemd-resolve"
                  type: "process"
                - name: "snapd"
                  type: "process"
            - name: "nginx process and port"
              type: "group"
              operator: "all"
              elements:
                - name: "nginx"
                  type: "process"
                - name: "nginx port 80"
                  type: "port"
                  port: 80
                  protocol: "tcp"
                  address: "0.0.0.0"
                - name: "nginx port 443"
                  type: "port"
                  port: 443
                  protocol: "tcp"
                  address: "::"
    routing:
      - routing_type: "ospf"
        ip_mask: "1.1.1.1/32"
        area: "0.0.0.0"
        interface: "dummy0"
EOL

read -r -d '' DAEMON_SCRIPT_CONTENT <<EOL
#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "\$FindBin::Bin/lib";
use Anycast;

# Configuration
my \$config_file = '${CONFIG_FILE_DEST}';

# Create Anycast object and start the daemon
Anycast->new(config_file => \$config_file)->daemon();
EOL

# Create and copy files
create_file "$SERVICE_FILE_CONTENT" "$SERVICE_FILE_DEST"
create_file "$CONFIG_FILE_CONTENT" "$CONFIG_FILE_DEST"
create_file "$DAEMON_SCRIPT_CONTENT" "$DAEMON_SCRIPT_DEST"
chmod +x "$DAEMON_SCRIPT_DEST"

# Reload systemd and enable the service
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Enabling $SERVICE_NAME..."
sudo systemctl enable "$SERVICE_NAME"

echo "Starting $SERVICE_NAME..."
sudo systemctl start "$SERVICE_NAME"

echo "Checking $SERVICE_NAME status..."
sudo systemctl status "$SERVICE_NAME"

