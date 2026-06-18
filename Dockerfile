# syntax=docker/dockerfile:1

ARG GO_VERSION=1.26.4
ARG ALPINE_VERSION=3.19

FROM golang:${GO_VERSION} AS amneziawg-go-builder

ARG AMNEZIAWG_GO_REF=v0.2.19

WORKDIR /src/amneziawg-go

RUN git clone --depth 1 --branch "${AMNEZIAWG_GO_REF}" https://github.com/amnezia-vpn/amneziawg-go.git . \
    && go mod download \
    && go mod verify \
    && go build -trimpath \
        -ldflags '-linkmode external -extldflags "-fno-PIC -static"' \
        -v \
        -o /usr/bin/amneziawg-go .

FROM alpine:${ALPINE_VERSION}

ARG ALPINE_VERSION
ARG AWGTOOLS_RELEASE=1.0.20260618-2
ARG AWGTOOLS_SHA256=b931875c44a932e5629bc05e85e25ecce0d3b66a8767730bf3014c1a05cbf167

RUN apk --no-cache add \
        bash \
        ca-certificates \
        iproute2 \
        iptables \
        openresolv \
        unzip \
        wget \
    && cd /usr/bin \
    && wget -O amneziawg-tools.zip "https://github.com/amnezia-vpn/amneziawg-tools/releases/download/v${AWGTOOLS_RELEASE}/alpine-${ALPINE_VERSION}-amneziawg-tools.zip" \
    && echo "${AWGTOOLS_SHA256}  amneziawg-tools.zip" | sha256sum -c - \
    && unzip -j amneziawg-tools.zip \
    && rm amneziawg-tools.zip \
    && chmod +x /usr/bin/awg /usr/bin/awg-quick \
    && ln -sf /usr/bin/awg /usr/bin/wg \
    && ln -sf /usr/bin/awg-quick /usr/bin/wg-quick \
    && mkdir -p /etc/amnezia/amneziawg /var/run/amneziawg

COPY --from=amneziawg-go-builder /usr/bin/amneziawg-go /usr/bin/amneziawg-go

ENV WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go

VOLUME ["/etc/amnezia/amneziawg"]

CMD ["awg-quick", "--help"]
