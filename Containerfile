# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY /build_files /build_files

# Base Image
FROM ghcr.io/ublue-os/bluefin-dx:latest
## Other possible base images include:
# ghcr.io/ublue-os/bazzite:latest
# quay.io/fedora/fedora-bootc:latest
# quay.io/centos-bootc/centos-bootc:stream10

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/build.sh
