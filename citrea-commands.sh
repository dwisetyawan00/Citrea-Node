#!/bin/bash

echo "=== Citrea & Bitcoin Node Commands ==="

echo -e "\n=== 1. Basic Status Commands ==="
echo "# Cek status sinkronisasi Citrea"
echo "curl -X POST --header \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"citrea_syncStatus\",\"params\":[], \"id\":31}' http://0.0.0.0:8080"

echo -e "\n# Cek status Bitcoin node"
echo "curl --user citrea:citrea --data-binary '{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"getblockcount\", \"params\": []}' -H 'content-type: text/plain;' http://0.0.0.0:18443"

echo -e "\n=== 2. Log Commands ==="
echo "# Lihat log Bitcoin node realtime"
echo "docker logs -f bitcoin-testnet4"

echo "# Lihat 100 baris terakhir log Bitcoin"
echo "docker logs --tail 100 bitcoin-testnet4"

echo "# Lihat log Citrea (jika dijalankan sebagai proses)"
echo "ps aux | grep citrea"
echo "tail -f citrea-node/citrea.log"    # Jika log file ada

echo -e "\n=== 3. Container Management ==="
echo "# Cek status container Bitcoin"
echo "docker ps | grep bitcoin-testnet4"

echo "# Restart Bitcoin node"
echo "docker restart bitcoin-testnet4"

echo "# Stop Bitcoin node"
echo "docker stop bitcoin-testnet4"

echo "# Start Bitcoin node"
echo "docker start bitcoin-testnet4"

echo -e "\n=== 4. Resource Usage ==="
echo "# Cek penggunaan resource Bitcoin container"
echo "docker stats bitcoin-testnet4"

echo "# Cek penggunaan disk"
echo "du -h citrea-node/"

echo "# Cek penggunaan memory proses Citrea"
echo "ps aux | grep citrea-v0.5.4-linux-amd64"

echo -e "\n=== 5. Network Commands ==="
echo "# Cek port yang digunakan"
echo "netstat -tulpn | grep -E '8080|18443'"

echo "# Cek koneksi Bitcoin node"
echo "curl --user citrea:citrea --data-binary '{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"getpeerinfo\", \"params\": []}' -H 'content-type: text/plain;' http://0.0.0.0:18443"

echo -e "\n=== 6. Troubleshooting ==="
echo "# Cek versi Bitcoin node"
echo "docker exec bitcoin-testnet4 bitcoin-cli --version"

echo "# Cek info Bitcoin node"
echo "curl --user citrea:citrea --data-binary '{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"getnetworkinfo\", \"params\": []}' -H 'content-type: text/plain;' http://0.0.0.0:18443"

echo "# Restart Citrea process (jika perlu)"
echo "pkill -f citrea-v0.5.4-linux-amd64"
echo "cd citrea-node && ./citrea-v0.5.4-linux-amd64 --da-layer bitcoin --rollup-config-path ./rollup_config.toml --genesis-paths ./genesis &"

echo -e "\n=== 7. Cleanup Commands ==="
echo "# Stop dan hapus Bitcoin container"
echo "docker stop bitcoin-testnet4"
echo "docker rm bitcoin-testnet4"

echo "# Hapus Bitcoin image"
echo "docker rmi bitcoin/bitcoin:28.0rc1"

echo "# Hapus data Citrea"
echo "rm -rf citrea-node/"

echo -e "\n=== Tips ==="
echo "1. Selalu cek logs jika ada masalah"
echo "2. Bitcoin node perlu waktu untuk sync penuh"
echo "3. Backup config files sebelum modifikasi"
echo "4. Monitor penggunaan disk secara berkala"
