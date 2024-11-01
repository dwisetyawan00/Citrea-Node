# AUTO Install & Setup Citrea Node

![bANNER](https://pbs.twimg.com/media/Gaq3EfuasAAFtlG?format=jpg&name=large)

# 🖥️ Hardware Requirements

| Component | Minimum Specs | Recommended Specs |
|-----------|--------------|-------------------|
| CPU | 2 Cores | 4 Cores |
| RAM | 4 GB | 8 GB |
| Storage | 100 GB SSD | 200 GB SSD |
| Network | 10 Mbps | 100 Mbps |

# 💻 Software Requirements

| Component | Minimum Version | Recommended Version |
|-----------|----------------|---------------------|
| OS | Ubuntu 20.04 | Ubuntu 22.04 |
| Ports | 30333, 9933, 9944 | 30333, 9933, 9944 |

# 🌐 Network Bandwidth

| Usage | Per Day | Per Month |
|-------|---------|-----------|
| Download | ~1-2 GB | ~30-60 GB |
| Upload | ~2-4 GB | ~60-120 GB |

# ⚡ Quick Installation
```bash
wget https://raw.githubusercontent.com/dwisetyawan00/Citrea-Node/main/citrea-setup.sh && chmod +x citrea-setup.sh && sudo ./citrea-setup.sh
```

# 📝 Check Logs
```bash
# View live logs
journalctl -u citread -f

# View last 100 lines
journalctl -u citread -n 100

# View today's logs
journalctl -u citread --since today
```

# ⚙️ Service Management
```bash
# Check status
sudo systemctl status citread

# Restart node
sudo systemctl restart citread

# Stop node
sudo systemctl stop citread

# Start node
sudo systemctl start citread
```
