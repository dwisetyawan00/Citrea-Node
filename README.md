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

# Install Docker
```bash
sudo apt update && sudo apt upgrade -y
```
### Install dependencies
```bash
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
sudo apt-get install -y net-tools netcat curl wget jq gpg tar lsof
```
# ⚡ Quick Installation
```bash
wget https://raw.githubusercontent.com/dwisetyawan00/Citrea-Node/main/citrea-setup.sh && chmod +x citrea-setup.sh && sudo ./citrea-setup.sh
```

## *SEBELUM CREATE WALLET PASTIKAN BLOCK SUDAH TERCAPAI*

# 👛 Auto Generate Wallet
### Create new wallet
```bash
wget https://raw.githubusercontent.com/dwisetyawan00/Citrea-Node/main/create-wallet.sh && chmod +x create-wallet.sh && sudo ./create-wallet.sh
```

# 📝 Check Logs
```bash
wget https://raw.githubusercontent.com/dwisetyawan00/Citrea-Node/main/check-node.sh && chmod +x check-node.sh && sudo ./check-node.sh
```
### Sebeleum menjalankan pastikan berada di direcotry ayng bersikan *`./check-node.sh*`
```bash
./check-node.sh
```
### Untuk melihat node sync setiap 10 dtk
```bash
./check_nodes.sh --monitor
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
## Manual Create & Backup Wallet
```bash
curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "createwallet", "params": ["nama_wallet_baru"]}' -H 'content-type: text/plain;' http://0.0.0.0:18443
```
- Ganti "nama_wallet_baru" dengan nama wallet yang Anda inginkan
### Memastikan wallet terload
```bash
curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listwallets", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:18443
```
### Get new address
```bash
curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getnewaddress", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:18443
```
# 🔑 Backup Private Key
### Mendapatkan semua descriptor termasuk private key
```bash
curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listdescriptors", "params": [true]}' -H 'content-type: text/plain;' http://0.0.0.0:18443
```
### Untuk mendapatkan info detail wallet
```bash
curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getwalletinfo", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:18443
```

# Untuk mendapatkan info detail address tertentu
```bash
curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getaddressinfo", "params": ["ADDRESS_YANG_DIDAPAT"]}' -H 'content-type: text/plain;' http://0.0.0.0:18443
```
- Ganti "ADDRESS_YANG_DIDAPAT" dengan address yang didapat dari command getnewaddress
- Private key akan muncul dalam format tprv dari hasil listdescriptors
- Simpan private key (tprv...) dengan aman karena ini adalah master key untuk wallet Anda

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
