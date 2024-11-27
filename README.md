# Anycast Daemon Installation

**Anycast Daemon** is a Perl-based application designed for monitoring and managing anycast services. This guide explains how to install and configure the application using the provided `install.sh` script.

---

## Features
- **Service Monitoring**: Monitors processes and ports for defined services.
- **Gateway Monitoring**: Uses `dpinger` to check gateway reachability.
- **Routing Management**: Automates OSPF configurations based on monitoring results.
- **Xymon Integration**: Reports statuses to a Xymon server.
- **Systemd Service**: Configured as a persistent systemd service.

---

## Installation

### Prerequisites
Ensure the following are installed:
- **Perl** (v5.10+)
- Perl Modules:
  - `FindBin`
  - `YAML::XS`
  - `JSON`
- **dpinger**: For gateway monitoring.
- **Xymon**: For status reporting.
- System utilities: `pgrep`, `vtysh`.

---

### Installation Steps

1. **Clone the Repository**
   ```bash
   git clone git@github.com:bonomani/anycast-daemon.git /opt/anycast
   cd /opt/anycast
   ```

2. **Update `install.sh` with Desired Paths**
   The `install.sh` script allows customization of key installation paths:
   - **Static Base Directory (`STATIC_BASE_DIR`)**: Where application files are stored.
   - **Runtime Base Directory (`RUNTIME_BASE_DIR`)**: For runtime files like logs and status files.
   - **Configuration Directory (`CONFIG_DIR`)**: Location for configuration files.
   - **Log Directory (`LOG_DIR`)**: Path for log storage.

   Edit the script to adjust these paths as needed:
   ```bash
   nano install.sh
   ```

   Example default configuration in `install.sh`:
   ```bash
   STATIC_BASE_DIR="/opt/anycast"
   RUNTIME_BASE_DIR="/opt/anycast/var"
   CONFIG_DIR="/etc/anycast"
   LOG_DIR="/var/log/anycast"
   ```

   Modify these paths if your setup requires different directories.

3. **Run the Installation Script**
   After updating paths, execute the script:
   ```bash
   sudo bash install.sh
   ```

   This will:
   - Create necessary directories.
   - Copy library files (`lib`) to `/opt/anycast/lib`.
   - Configure a systemd service (`anycast.service`).
   - Start the service.

4. **Verify the Service**
   Check the service status:
   ```bash
   sudo systemctl status anycast.service
   ```

---

## Configuration

The application configuration is located at `/etc/anycast/config.yml`. Below is an example:

```yaml
static_base_dir: "/opt/anycast"
runtime_base_dir: "/opt/anycast/var"
state_file: "{{ runtime_base_dir }}/anycast_status.json"
log_level: "DEBUG"
log_file: "/var/log/anycast/anycast_daemon.log"
interval: 10

dpinger:
  exec_path: "/usr/local/bin/dpinger"
  bind_address: "0.0.0.0"

controllers:
  - name: "Controller 1"
    service_monitoring:
      elements:
        - name: "gateway1"
          type: "gateway"
          ip: "192.168.1.3"
        - name: "postfix"
          type: "process"
```

---

## Usage

### Start and Stop the Service
- **Start the Service**:
  ```bash
  sudo systemctl start anycast.service
  ```
- **Stop the Service**:
  ```bash
  sudo systemctl stop anycast.service
  ```

### View Logs
Logs are stored in `/var/log/anycast/anycast_daemon.log`:
```bash
tail -f /var/log/anycast/anycast_daemon.log
```

### Test the Daemon
Run the daemon manually for testing:
```bash
perl /opt/anycast/anycast_daemon.pl
```

---

## Contributing

1. **Fork the Repository**:
   ```bash
   git clone git@github.com:bonomani/anycast-daemon.git
   cd anycast-daemon
   ```

2. **Create a Feature Branch**:
   ```bash
   git checkout -b feature-name
   ```

3. **Commit Your Changes**:
   ```bash
   git commit -m "Description of changes"
   ```

4. **Push and Submit a Pull Request**:
   ```bash
   git push origin feature-name
   ```

---

## License

This project is licensed under the [MIT License](LICENSE).

---

Let me know if additional details are required!
