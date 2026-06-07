# ServerPulse MOTD

A colorful system dashboard and MOTD (Message of the Day) for Ubuntu/Debian and RHEL/RPM-based servers displayed on SSH login.

## Overview

ServerPulse MOTD installs a dynamic system dashboard that displays comprehensive server metrics when users log in via SSH. It provides real-time visibility into system health, resource usage, and security status without requiring PAM configuration.

![ServerPulse MOTD Dashboard](image/serverpulse.png)

## Features

### System Information

- Hostname, OS version, kernel, IP addresses (local & public)
- System uptime

### Performance Metrics

- CPU load and usage with visual progress bars
- Memory usage (RAM and swap) with visual indicators
- Disk space and inode usage
- Disk I/O statistics

### GPU Monitoring

- NVIDIA GPU detection and support
- GPU utilization and memory usage
- GPU temperature and power draw
- CUDA version tracking

### SSH & Security

- Active SSH session count
- Last login information
- Failed login attempt tracking
- Pending system updates and security patches
- Firewall status
  - UFW on Ubuntu/Debian
  - firewalld on RHEL/RPM-based systems
- System reboot requirement status

### Network

- Network interface details
- RX/TX bytes transferred
- DNS configuration
- Gateway information

## Installation

### From DEB Package

For Ubuntu/Debian-based systems:

```bash
# Build the package
./build-serverpulse-motd-deb.sh

# Install
sudo dpkg -i serverpulse-motd_1.6.0_all.deb
```

### From RPM Package

For RHEL, Rocky Linux, AlmaLinux, CentOS, Fedora, and other RPM-based systems:

```bash
# Build the RPM package
./build-serverpulse-motd-rpm.sh

# Install using dnf
sudo dnf install -y dist-rpm/serverpulse-motd-1.6.0-1*.noarch.rpm
```

Alternative install using `rpm`:

```bash
sudo rpm -Uvh dist-rpm/serverpulse-motd-1.6.0-1*.noarch.rpm
```

### Manual Installation

```bash
# Copy MOTD script
sudo cp serverpulse-motd /usr/local/bin/serverpulse-motd
sudo chmod 755 /usr/local/bin/serverpulse-motd

# Copy profile.d script
sudo cp serverpulse.sh /etc/profile.d/serverpulse.sh
sudo chmod 755 /etc/profile.d/serverpulse.sh
```

For Ubuntu/Debian:

```bash
# Update SSH config
sudo sed -i 's/^#*PrintMotd .*/PrintMotd no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PrintLastLog .*/PrintLastLog no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

For RHEL/RPM-based systems:

```bash
# Update SSH config
sudo sed -i 's/^#*PrintMotd .*/PrintMotd no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PrintLastLog .*/PrintLastLog no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

## Testing

### Manual Test

Run the dashboard directly:

```bash
/usr/local/bin/serverpulse-motd
```

### SSH Test

Log out and SSH back in:

```bash
exit
ssh user@server-ip
```

## Requirements

### Debian/Ubuntu Dependencies

- bash
- coreutils
- procps
- iproute2
- curl
- apt

### RHEL/RPM Dependencies

- bash
- coreutils
- procps-ng
- iproute
- curl
- dnf or yum

### Recommended

- ufw for Ubuntu/Debian firewall status
- firewalld for RHEL/RPM firewall status
- nvidia-utils or NVIDIA driver tools for GPU monitoring

## How It Works

- Runs via `/etc/profile.d/serverpulse.sh` on interactive SSH sessions
- Executes `/usr/local/bin/serverpulse-motd` during SSH login
- Collects system metrics from `/proc`, `/sys`, and standard system utilities
- Displays color-coded status:
  - Green: healthy
  - Yellow: caution
  - Red: alert
- Uses lightweight cache files in `/tmp/serverpulse-cache-*`
- No persistent daemon required

## Build Output

### DEB

```bash
serverpulse-motd_1.6.0_all.deb
```

### RPM

```bash
dist-rpm/serverpulse-motd-1.6.0-1.noarch.rpm
```

## Uninstallation

### Debian/Ubuntu

```bash
sudo dpkg -r serverpulse-motd
```

### RHEL/RPM-based Systems

```bash
sudo dnf remove -y serverpulse-motd
```

Or:

```bash
sudo rpm -e serverpulse-motd
```

## License

Created by Ali Mustofa <hai.alimustofa@gmail.com>  
Visit: https://alimustofa.my.id
