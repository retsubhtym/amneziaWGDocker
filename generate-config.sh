#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  ./generate-config.sh --endpoint <public-host-or-ip> [options]

Options:
  --endpoint <host>       Public server hostname or IP used in the client config.
  --port <port>           UDP listen port. Default: 51820.
  --server-ip <cidr>      Server tunnel address. Default: 10.8.0.1/24.
  --client-ip <cidr>      Client tunnel address. Default: 10.8.0.2/32.
  --vpn-cidr <cidr>       VPN subnet used for container NAT. Default: 10.8.0.0/24.
  --dns <servers>         Client DNS servers. Default: 1.1.1.1, 9.9.9.9.
  --output-dir <dir>      Directory for generated files. Default: .
  --force                 Overwrite existing awg0.conf/client.conf.
  -h, --help              Show this help.

Generated files:
  awg0.conf               Server config consumed by docker-compose.yml.
  client.conf             Client config to import into an AmneziaWG client.
EOF
}

endpoint=""
port="51820"
server_ip="10.8.0.1/24"
client_ip="10.8.0.2/32"
vpn_cidr="10.8.0.0/24"
dns="1.1.1.1, 9.9.9.9"
output_dir="."
force=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --endpoint)
      endpoint="${2:-}"
      shift 2
      ;;
    --port)
      port="${2:-}"
      shift 2
      ;;
    --server-ip)
      server_ip="${2:-}"
      shift 2
      ;;
    --client-ip)
      client_ip="${2:-}"
      shift 2
      ;;
    --vpn-cidr)
      vpn_cidr="${2:-}"
      shift 2
      ;;
    --dns)
      dns="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$endpoint" ]; then
  echo "Missing required --endpoint <public-host-or-ip>." >&2
  exit 2
fi

case "$port" in
  *[!0-9]*|"")
    echo "--port must be a number." >&2
    exit 2
    ;;
esac

if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  echo "--port must be between 1 and 65535." >&2
  exit 2
fi

mkdir -p "$output_dir"
server_conf="$output_dir/awg0.conf"
client_conf="$output_dir/client.conf"
env_file="$output_dir/.env"

if [ "$force" -ne 1 ]; then
  for file in "$server_conf" "$client_conf"; do
    if [ -e "$file" ]; then
      echo "$file already exists. Use --force to overwrite." >&2
      exit 1
    fi
  done
fi

umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if command -v awg >/dev/null 2>&1; then
  awg() {
    command awg "$@"
  }
elif command -v wg >/dev/null 2>&1; then
  awg() {
    command wg "$@"
  }
elif command -v docker >/dev/null 2>&1; then
  if ! docker image inspect amneziawg:local >/dev/null 2>&1; then
    echo "Building amneziawg:local so the official awg tool can generate keys..." >&2
    docker build -t amneziawg:local "$script_dir" >/dev/null
  fi
  awg() {
    docker run --rm -i amneziawg:local awg "$@"
  }
else
  echo "Neither awg/wg nor docker was found. Install Docker or amneziawg-tools first." >&2
  exit 1
fi

server_private="$(awg genkey)"
server_public="$(printf '%s\n' "$server_private" | awg pubkey)"
client_private="$(awg genkey)"
client_public="$(printf '%s\n' "$client_private" | awg pubkey)"
preshared_key="$(awg genpsk)"

cat > "$server_conf" <<EOF
[Interface]
PrivateKey = $server_private
Address = $server_ip
ListenPort = $port
Jc = 4
Jmin = 64
Jmax = 512
S1 = 32
S2 = 32
S3 = 32
S4 = 16
H1 = 1-1073741823
H2 = 1073741824-2147483647
H3 = 2147483648-3221225471
H4 = 3221225472-4294967295
PostUp = iptables -t nat -A POSTROUTING -s $vpn_cidr -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s $vpn_cidr -o eth0 -j MASQUERADE

[Peer]
PublicKey = $client_public
PresharedKey = $preshared_key
AllowedIPs = ${client_ip%/*}/32
EOF

cat > "$client_conf" <<EOF
[Interface]
PrivateKey = $client_private
Address = $client_ip
DNS = $dns
Jc = 4
Jmin = 64
Jmax = 512
S1 = 32
S2 = 32
S3 = 32
S4 = 16
H1 = 1-1073741823
H2 = 1073741824-2147483647
H3 = 2147483648-3221225471
H4 = 3221225472-4294967295

[Peer]
PublicKey = $server_public
PresharedKey = $preshared_key
Endpoint = $endpoint:$port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 "$server_conf" "$client_conf"

if [ ! -e "$env_file" ] || [ "$force" -eq 1 ]; then
  printf 'AMNEZIAWG_PORT=%s\n' "$port" > "$env_file"
  chmod 600 "$env_file"
fi

cat <<EOF
Generated:
  $server_conf
  $client_conf
  $env_file

Next:
  docker compose up -d --build

Import client.conf into your AmneziaWG client.
EOF
