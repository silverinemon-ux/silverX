FROM rust:1.85-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libssl-dev \
    git-all \
    protobuf-compiler \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN rustup toolchain install nightly-2025-04-06
RUN rustup default nightly-2025-04-06

ENV RUSTUP_TOOLCHAIN=nightly-2025-04-06
RUN cargo install --git https://github.com/nexus-xyz/nexus-cli --tag v0.10.17 nexus-network

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    ca-certificates \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/cargo/bin/nexus-network /usr/local/bin/nexus-cli

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN useradd -m nexususer
USER nexususer
WORKDIR /home/nexususer

ENV NEXUS_HOME=/home/nexususer/.nexus

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
