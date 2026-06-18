# AmneziaWG Docker Image

This Dockerfile uses only official sources:

- AmneziaWG documentation: https://docs.amnezia.org/documentation/amnezia-wg/
- Official `amneziawg-go` repository: https://github.com/amnezia-vpn/amneziawg-go
- Official `amneziawg-tools` repository and release assets: https://github.com/amnezia-vpn/amneziawg-tools

Default versions:

- `amneziawg-go`: `v0.2.19`
- `amneziawg-tools`: `v1.0.20260618-2`
- Protocol support: AmneziaWG 2.0+

Build:

```sh
docker build -t amneziawg:local .
```

Run with Docker Compose:

```sh
./generate-config.sh --endpoint <your-server-public-ip-or-hostname>
docker compose up -d --build
```

The generator creates `awg0.conf`, `client.conf`, and `.env`. Set `--port` if
you want a UDP port other than `51820`.
Do not commit `awg0.conf` or `client.conf`; they contain private keys and are ignored by Git.
Import the generated `client.conf` into your AmneziaWG client.
If you generated configs before this version, regenerate them with `--force` so
the `H1`-`H4` ranges use the userspace-compatible `start-end` format.

If Docker already created `awg0.conf` as a directory, remove it first:

```sh
rmdir awg0.conf
```

Run with an AmneziaWG config mounted as `/etc/amnezia/amneziawg/awg0.conf`:

```sh
docker run --rm -it \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -p 51820:51820/udp \
  -v "$PWD/awg0.conf:/etc/amnezia/amneziawg/awg0.conf:ro" \
  amneziawg:local \
  sh -c 'set -e; awg-quick up awg0; trap "awg-quick down awg0" INT TERM EXIT; while true; do sleep 3600 & wait $!; done'
```

The image uses the official userspace implementation, `amneziawg-go`, because Docker containers cannot portably install or manage a host Linux kernel module.
