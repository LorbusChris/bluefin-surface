# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY /build_files /build_files

# Base Image
FROM ghcr.io/ublue-os/bluefin-dx:latest
## Other possible base images include:
# ghcr.io/ublue-os/bazzite:latest
# quay.io/fedora/fedora-bootc:41
# quay.io/centos-bootc/centos-bootc:stream10

RUN --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/var \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/build.sh
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint