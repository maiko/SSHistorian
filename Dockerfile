FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    bash \
    sqlite3 \
    openssh-client \
    python3 \
    python3-pip \
    pipx \
    shellcheck \
    git \
    curl

RUN pipx ensurepath

# Install TermRecord
RUN pipx install TermRecord

# Install bats-core
RUN git clone https://github.com/bats-core/bats-core.git \
    && cd bats-core \
    && ./install.sh /usr/local \
    && cd .. \
    && rm -rf bats-core

# Install bats-support and bats-assert
RUN mkdir -p /usr/local/lib/bats \
    && git clone https://github.com/bats-core/bats-support.git /usr/local/lib/bats/bats-support \
    && git clone https://github.com/bats-core/bats-assert.git /usr/local/lib/bats/bats-assert

WORKDIR /app

ENV TERM=xterm-256color