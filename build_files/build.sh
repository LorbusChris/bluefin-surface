#!/bin/bash
set -xeuo pipefail

# Remove Existing Kernel
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
        kmod-xone kmod-openrazer kmod-framework-laptop kmod-v4l2loopback v4l2loopback; do
    rpm --erase $pkg --nodeps
done

# Fetch Common AKMODS & Kernel RPMS
skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods:bazzite-"$(rpm -E %fedora)" dir:/tmp/akmods
AKMODS_TARGZ=$(jq -r '.layers[].digest' </tmp/akmods/manifest.json | cut -d : -f 2)
tar -xvzf /tmp/akmods/"$AKMODS_TARGZ" -C /tmp/
mv /tmp/rpms/* /tmp/akmods/
# NOTE: kernel-rpms should auto-extract into correct location

# Print some info
tree /tmp/akmods/
cat /etc/dnf/dnf.conf
cat /etc/yum.repos.d/*

# Install Kernel
dnf -y install --setopt=disable_excludes=* \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

dnf -y copr enable ublue-os/staging
dnf -y copr enable ublue-os/packages
dnf -y copr enable ublue-os/akmods

dnf -y install \
    v4l2loopback /tmp/akmods/kmods/*v4l2loopback*.rpm

dnf -y copr enable ublue-os/staging
dnf -y copr enable ublue-os/packages
dnf -y copr enable ublue-os/akmods

# Configure surface kernel modules to load at boot
tee /usr/lib/modules-load.d/ublue-surface.conf << EOF
# Only on AMD models
pinctrl_amd

# Surface Book 2
pinctrl_sunrisepoint

# For Surface Laptop 3/Surface Book 3
pinctrl_icelake

# For Surface Laptop 4/Surface Laptop Studio
pinctrl_tigerlake

# For Surface Pro 9/Surface Laptop 5
pinctrl_alderlake

# For Surface Pro 10/Surface Laptop 6
pinctrl_meteorlake

# Only on Intel models
intel_lpss
intel_lpss_pci

# Add modules necessary for Disk Encryption via keyboard
surface_aggregator
surface_aggregator_registry
surface_aggregator_hub
surface_hid_core
8250_dw

# Surface Laptop 3/Surface Book 3 and later
surface_hid
surface_kbd

EOF

dnf config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
# Pin to surface-linux fedora 42 repo for now
sed -i 's|^baseurl=https://pkg.surfacelinux.com/fedora/f$releasever/|baseurl=https://pkg.surfacelinux.com/fedora/f42/|' /etc/yum.repos.d/linux-surface.repo
dnf config-manager setopt linux-surface.enabled=0
dnf -y install --enablerepo="linux-surface" \
    iptsd
dnf -y swap --repo="linux-surface" \
    libwacom-data libwacom-surface-data
dnf -y swap --repo="linux-surface" \
    libwacom libwacom-surface

# Install additional fedora packages
ADDITIONAL_FEDORA_PACKAGES=(
    gdb
    v4l-utils
    libcamera-qcam
    #pipewire-v4l2
    nextcloud-client-nautilus
    firefox
    chromium
    pmbootstrap
    #calls
    feedbackd
    gnome-network-displays
)

dnf -y install --skip-unavailable \
    "${ADDITIONAL_FEDORA_PACKAGES[@]}"

# calls-49.1.1-1.fc43
#dnf -y upgrade --repo=updates-testing --refresh --advisory=FEDORA-2025-22ad4cfabc
# feedbackd-0.8.6-3.fc43
dnf -y upgrade --repo=updates-testing --refresh --advisory=FEDORA-2025-147f8170eb

# Regenerate initramfs
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

# Cleanup
dnf clean all

find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find /var/cache/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;

# Bootc
bootc container lint 
