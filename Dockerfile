# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.24.1

FROM alpine:${ALPINE_VERSION} AS builder

COPY mergerfs-version.txt /tmp/mergerfs-version.txt

RUN set -eu; \
    apk add --no-cache g++ git linux-headers make; \
    mergerfs_version="$(tr -d '[:space:]' < /tmp/mergerfs-version.txt)"; \
    test -n "$mergerfs_version"; \
    git clone --depth 1 --branch "$mergerfs_version" https://github.com/trapexit/mergerfs /tmp/mergerfs; \
    make -C /tmp/mergerfs RELEASE=1 NDEBUG=1 LTO=1 STATIC=1 DESTDIR=/tmp/install -j"$(nproc)" install-strip; \
    /tmp/install/usr/local/bin/mergerfs --version

FROM alpine:${ALPINE_VERSION} AS mergerfs-release

RUN set -eu; \
    apk add --no-cache fuse3; \
    mkdir -p /config /disks /merged

COPY --from=builder /tmp/install/usr/local/bin/mergerfs /usr/local/bin/mergerfs
COPY entrypoint.sh /entrypoint.sh
COPY parameters.conf /config/parameters.conf

RUN chmod 0755 /entrypoint.sh /usr/local/bin/mergerfs
RUN addgroup -g 568 abc && adduser -D -u 568 -G abc abc

ENTRYPOINT ["/entrypoint.sh"]
