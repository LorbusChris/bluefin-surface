#!/bin/bash
set -xeuo pipefail

# Remove Existing Kernel
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    rpm --erase $pkg --nodeps
done

# Fetch Common AKMODS & Kernel RPMS
skopeo copy --retry-times 3 docker://ghcr.io/ublue-os/akmods:bazzite-"$(rpm -E %fedora)" dir:/tmp/akmods
AKMODS_TARGZ=$(jq -r '.layers[].digest' </tmp/akmods/manifest.json | cut -d : -f 2)
tar -xvzf /tmp/akmods/"$AKMODS_TARGZ" -C /tmp/
mv /tmp/rpms/* /tmp/akmods/
# NOTE: kernel-rpms should auto-extract into correct location
cat /etc/dnf/dnf.conf
cat /etc/yum.repos.d/*

# Install Kernel
dnf --setopt=disable_excludes=* -y install \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

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

# Install surface packages
SURFACE_PACKAGES=(
    iptsd
)
dnf config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
# Pin to surface-linux fedora 42 repo for now
sed -i 's|^baseurl=https://pkg.surfacelinux.com/fedora/f$releasever/|baseurl=https://pkg.surfacelinux.com/fedora/f42/|' /etc/yum.repos.d/linux-surface.repo
dnf config-manager setopt linux-surface.enabled=0
dnf install -y --enablerepo="linux-surface" \
    "${SURFACE_PACKAGES[@]}"
dnf swap -y --enablerepo="linux-surface" \
    libwacom-data libwacom-surface-data
dnf swap -y --enablerepo="linux-surface" \
    libwacom libwacom-surface
dnf swap -y --enablerepo="fedora-updates-testing" \
    calls calls

# Install additional fedora packages
ADDITIONAL_FEDORA_PACKAGES=(
    #libcamera
    #libcamera-tools
    #libcamera-gstreamer
    #libcamera-ipa
    #pipewire-plugin-libcamera
    #pipewire-v4l2
    nextcloud-client-nautilus
    firefox
    calls
    feedbackd
    gnome-network-displays
)

dnf -y install --skip-unavailable \
    "${ADDITIONAL_FEDORA_PACKAGES[@]}"

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
