Here’s a sample `README.md` file for your Anycast Daemon application:

---

# Anycast Daemon

**Anycast Daemon** is a Perl-based application designed to monitor and manage anycast services, gateways, and network processes. It utilizes configuration files and integrates with tools like `dpinger` for monitoring, Xymon for notifications, and system utilities for managing routing states.

---

## Features

- **Gateway Monitoring**: Monitors multiple gateways and reports their operational status.
- **Service Monitoring**: Checks processes and ports, ensuring critical services are running.
- **Routing Management**: Manages routing configurations (e.g., OSPF) based on monitoring results.
- **Integration with Xymon**: Sends alerts and notifications to a configured Xymon server.
- **Customizable**: Configurable through YAML files for flexibility and scalability.

---

## Requirements

### Software Dependencies
- **Perl** (v5.10+)
- Perl Modules:
  - `FindBin`
  - `YAML::XS`
  - `JSON`
  - `File::Slurp`
- **dpinger**: For gateway monitoring.
- **Xymon**: For status reporting.
- System utilities:
  - `pgrep`
  - `vtysh`

---

## Installation

1. **Clone the Repository**
   ```bash
   git clone git@github.com:bonomani/anycast-daemon.git /opt/anycast
   cd /opt/anycast
   ```

2. **Run the Installer**
   ```bash
   sudo bash install.sh
   ```

   This script will:
   - Install required files in `/opt/anycast`.
   - Set up configuration in `/etc/anycast/config.yml`.
   - Create a systemd service for the daemon.

3. **Start the Service**
   ```bash
   sudo systemctl start anycast.service
   ```

4. **Enable the Service at Boot**
   ```bash
   sudo systemctl enable anycast.service
   ```

---

## Configuration

The application is configured through `/etc/anycast/config.yml`. Below is a sample configuration:

```yaml
name: "global_monitor"
log_level: "DEBUG"
static_base_dir: "/opt/anycast"
runtime_base_dir: "/opt/anycast/var"
state_file: "{{ runtime_base_dir }}/anycast_status.json"

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
```

---

## Usage

### Check Service Status
```bash
sudo systemctl status anycast.service
```

### View Logs
```bash
tail -f /var/log/anycast/anycast_daemon.log
```

### Test the Application
Run the daemon manually:
```bash
perl /opt/anycast/anycast_daemon.pl
```

---

## Contributing

1. Fork the repository.
2. Create a new branch:
   ```bash
   git checkout -b feature-name
   ```
3. Make your changes and commit them:
   ```bash
   git commit -m "Description of changes"
   ```
4. Push to your fork and submit a pull request.

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Author

**Bonomani**  
Feel free to reach out for support or questions about this project.

---

You can adjust or expand this `README.md` file as needed based on specific project requirements or additional features. Let me know if you'd like to add anything!
