# mergerfs Docker

A small Alpine-based container for running [mergerfs](https://github.com/trapexit/mergerfs) over directories that are already mounted on a Linux host.

The image builds the mergerfs release pinned in [`mergerfs-version.txt`](mergerfs-version.txt), combines every direct child directory under `/disks`, and exposes the resulting FUSE mount at `/merged`.

## Project scope

This project provides:

- a reproducible multi-stage build of mergerfs;
- a minimal runtime image with FUSE support;
- configurable mergerfs mount options; and
- startup, shutdown, and unmount handling for the FUSE process.

It does not mount physical disks, provide RAID or redundancy, expose network shares, manage users, or replace backups. Mount and prepare the source filesystems on the host before starting the container.

## Requirements

- A Linux host with FUSE available at `/dev/fuse`
- Docker Engine with permission to add the `SYS_ADMIN` capability
- One or more host directories to use as mergerfs branches
- A host directory for the merged mount, configured for shared mount propagation

`SYS_ADMIN` is a powerful capability. Run this image only on a trusted host and avoid adding unrelated software or untrusted configuration to the container.

## Build

Build the runtime target locally:

```bash
docker build \
  --target mergerfs-release \
  --tag mergerfs-docker:local \
  .
```

## Run with Docker

The following example combines `/mnt/disk1` and `/mnt/disk2` and publishes the mergerfs mount through `/mnt/merged`:

```bash
docker run --detach \
  --name mergerfs \
  --device /dev/fuse:/dev/fuse \
  --cap-add SYS_ADMIN \
  --mount type=bind,source=/mnt/disk1,target=/disks/disk1 \
  --mount type=bind,source=/mnt/disk2,target=/disks/disk2 \
  --mount type=bind,source=/mnt/merged,target=/merged,bind-propagation=shared \
  --restart unless-stopped \
  mergerfs-docker:local
```

Each directory directly below `/disks` becomes one mergerfs branch. The branch names are arbitrary, but every branch must be a directory.

## Run with Docker Compose

```yaml
services:
  mergerfs:
    build:
      context: .
      target: mergerfs-release
    image: mergerfs-docker:local
    container_name: mergerfs
    cap_add:
      - SYS_ADMIN
    devices:
      - /dev/fuse:/dev/fuse
    volumes:
      - type: bind
        source: /mnt/disk1
        target: /disks/disk1
      - type: bind
        source: /mnt/disk2
        target: /disks/disk2
      - type: bind
        source: /mnt/merged
        target: /merged
        bind:
          propagation: shared
    restart: unless-stopped
```

Start it with:

```bash
docker compose up --detach
```

The host path used for `/merged` must already exist and support shared propagation. If the merged filesystem is visible inside the container but not on the host, inspect the host mount with `findmnt -o TARGET,PROPAGATION /mnt/merged` and correct its propagation before restarting the container.

## Configuration

The default mergerfs options are documented in [`parameters.conf`](parameters.conf). Active options are read one per line; blank lines and lines beginning with `#` are ignored.

To provide a custom file, bind-mount it read-only:

```bash
docker run --detach \
  --name mergerfs \
  --device /dev/fuse:/dev/fuse \
  --cap-add SYS_ADMIN \
  --mount type=bind,source=/path/to/parameters.conf,target=/config/parameters.conf,readonly \
  --mount type=bind,source=/mnt/disk1,target=/disks/disk1 \
  --mount type=bind,source=/mnt/disk2,target=/disks/disk2 \
  --mount type=bind,source=/mnt/merged,target=/merged,bind-propagation=shared \
  mergerfs-docker:local
```

Alternatively, `MERGERFS_PARAMS` accepts a comma-separated option list and completely overrides the file:

```yaml
environment:
  MERGERFS_PARAMS: moveonenospc=true,dropcacheonclose=true,category.create=mfs,cache.files=partial
```

`MERGERFS_PARAMS` contains filesystem options only. The image does not require API keys, passwords, tokens, or other credentials. Do not place secrets in this variable or in `parameters.conf`.

## Runtime behavior

On startup, the entrypoint:

1. loads options from `MERGERFS_PARAMS` or `/config/parameters.conf`;
2. validates the branch directories under `/disks`;
3. clears a stale mergerfs mount at `/merged`, if present;
4. starts mergerfs in the foreground and checks that it mounted successfully; and
5. forwards shutdown signals and unmounts `/merged` during container shutdown.

View startup and shutdown messages with:

```bash
docker logs mergerfs
```

## Privacy and secrets

The container has no authentication system, network listeners, telemetry, or credential requirements. No secrets or personal data should be committed to this repository. Remember that files in the mounted branch directories are accessible from inside the container by design.

## Updating mergerfs

Change the version in [`mergerfs-version.txt`](mergerfs-version.txt), then rebuild the image. The Docker build checks out that exact upstream release and verifies the resulting binary.

## Acknowledgements

mergerfs is developed and maintained in the [upstream mergerfs project](https://github.com/trapexit/mergerfs). Its source and ISC license are available in the [upstream repository](https://github.com/trapexit/mergerfs/blob/master/LICENSE).
