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
- Pilih 2 Manual
  - Masukan nama node
  - Enter biarkan default

# 📝 Check Logs
```bash
tail -f citrea.log
```
# ⚙️ Service Management
## Monitoring Status:

- Cek sync Citrea: 
```bash
curl -X POST --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[], "id":31}' http://0.0.0.0:8080
```
- Cek Bitcoin node:
```bash
docker logs -f bitcoin-testnet4
```

## Troubleshooting:

- Cek status container: 
```bash
docker ps | grep bitcoin-testnet4
```
- Cek port: 
```bash
netstat -tulpn | grep -E '8080|18443'
```
- Cek resource usage: 
```bash
docker stats bitcoin-testnet4
```
## Restart Services:

- Bitcoin: 
```bash
docker restart bitcoin-testnet4
```
- Citrea:
```bash
pkill -f citrea-v0.5.4-linux-amd64
```
```bash
cd citrea-node
./citrea-v0.5.4-linux-amd64 --da-layer bitcoin --rollup-config-path ./rollup_config.toml --genesis-paths ./genesis &
```

## Cleanup:
```bash
docker stop bitcoin-testnet4
docker rm bitcoin-testnet4
docker rmi bitcoin/bitcoin:28.0rc1
rm -rf citrea-node/
```
