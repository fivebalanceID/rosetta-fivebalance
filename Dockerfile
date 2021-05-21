# Copyright 2020 Coinbase, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build fivebalanced
FROM ubuntu:18.04 as fivebalanced-builder
ENV LANG C.UTF-8

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app
WORKDIR /app

# Source: https://github.com/fivebalance/fivebalance/blob/master/doc/build-unix.md#ubuntu--debian
RUN set -xe; \
  apt-get update; \
  apt-get install --no-install-recommends --fix-missing -y build-essential autotools-dev bsdmainutils automake autotools-dev autoconf pkg-config wget git libboost-dev libboost-all-dev libboost-container-dev apt-utils libssl-dev libevent-dev libsodium-dev \
    librsvg2-bin cmake libcap-dev libdb++-dev libz-dev libtool libbz2-dev python-setuptools python3-setuptools xz-utils ccache cargo libgmp-dev \
    bsdmainutils curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    /usr/sbin/update-ccache-symlinks;

# VERSION: Fivebalance Core 3.3.0
RUN git clone https://github.com/fivebalanceID/Fivebalance_V3 \
  && cd Fivebalance_V3 

RUN cd Fivebalance_V3 \
  && ./autogen.sh \
  && ./configure --enable-static --with-pic --disable-shared --enable-glibc-back-compat --disable-tests --without-miniupnpc --without-gui --with-incompatible-bdb --disable-hardening --disable-zmq --disable-bench \
  && make

RUN mv Fivebalance_V3/src/fivebalanced /app/fivebalanced \
  && rm -rf Fivebalance_V3

RUN ldconfig

# Build Rosetta Server Components
FROM ubuntu:18.04 as rosetta-builder

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app
WORKDIR /app

RUN apt-get update && apt-get install -y curl make gcc g++
ENV GOLANG_VERSION 1.15.5
ENV GOLANG_DOWNLOAD_SHA256 9a58494e8da722c3aef248c9227b0e9c528c7318309827780f16220998180a0d
ENV GOLANG_DOWNLOAD_URL https://golang.org/dl/go$GOLANG_VERSION.linux-amd64.tar.gz

RUN curl -fsSL "$GOLANG_DOWNLOAD_URL" -o golang.tar.gz \
  && echo "$GOLANG_DOWNLOAD_SHA256  golang.tar.gz" | sha256sum -c - \
  && tar -C /usr/local -xzf golang.tar.gz \
  && rm golang.tar.gz

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

# Use native remote build context to build in any directory
COPY . src
## Cleanup
RUN cd src \
&& rm go.sum \
&& go mod edit -replace github.com/golang/lint=golang.org/x/lint@latest \
&& go clean -modcache

RUN cd src \
  && go build \
  && cd .. \
  && mv src/rosetta-fivebalance /app/rosetta-fivebalance \
  && mv src/assets/* /app \
  && rm -rf src 

## Build Final Image
FROM ubuntu:18.04

RUN apt-get update && \
  apt-get install -y --no-install-recommends libevent-dev libboost-system-dev libboost-filesystem-dev libboost-program-options-dev libdb5.3++-dev libboost-test-dev libboost-thread-dev libsodium-dev && \
  apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app \
  && mkdir -p /data \
  && chown -R nobody:nogroup /data

WORKDIR /app

# Copy binary from fivebalanced-builder
COPY --from=fivebalanced-builder /app/fivebalanced /app/fivebalanced

# Copy binary from rosetta-builder
COPY --from=rosetta-builder /app/* /app/

# Set permissions for everything added to /app
RUN chmod -R 755 /app/*

CMD ["/app/rosetta-fivebalance"]
