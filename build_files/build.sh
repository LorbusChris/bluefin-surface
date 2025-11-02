#!/bin/bash
set -xeuo pipefail

# Copy ISO list for `install-system-flatpaks`
install -Dm0644 -t /etc/ublue-os/ /ctx/flatpaks/*.list

# Remove Bluefin extensions
rm -rf /usr/share/gnome-shell/extensions/*

# Copy Files to Container
rsync -rvK /ctx/system_files/shared/ /

# Remove Existing Kernel
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-tools \
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

# Install Kernel
dnf -y install --setopt=disable_excludes=* \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-tools-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra kernel-tools

dnf -y install \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm
dnf -y install \
    v4l2loopback /tmp/akmods/kmods/*v4l2loopback*.rpm
dnf -y remove rpmfusion-free-release rpmfusion-nonfree-release

# Configure surface kernel modules to load at boot
tee /usr/lib/modules-load.d/ublue-surface.conf << EOF
# Add modules necessary for Disk Encryption via keyboard
surface_aggregator
surface_aggregator_registry
surface_aggregator_hub
surface_hid_core
8250_dw

# Surface Laptop 3/Surface Book 3 and later
surface_hid
surface_kbd

# Only on AMD models
pinctrl_amd

# Only on Intel models
intel_lpss
intel_lpss_pci

# Surface Book 2
pinctrl_sunrisepoint

# For Surface Pro 7/Laptop 3/Book 3
pinctrl_icelake

# For Surface Pro 7+/Pro 8/Laptop 4/Laptop Studio
pinctrl_tigerlake

# For Surface Pro 9/Laptop 5
pinctrl_alderlake

# For Surface Pro 10/Laptop 6
pinctrl_meteorlake

EOF

dnf config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
# Pin to surface-linux fedora 42 repo for now
sed -i 's|^baseurl=https://pkg.surfacelinux.com/fedora/f$releasever/|baseurl=https://pkg.surfacelinux.com/fedora/f42/|' /etc/yum.repos.d/linux-surface.repo
dnf config-manager setopt linux-surface.enabled=0
dnf -y install --repo="linux-surface" \
    iptsd
dnf -y swap --repo="linux-surface" \
    libwacom-data libwacom-surface-data
dnf -y swap --repo="linux-surface" \
    libwacom libwacom-surface

# Regenerate initramfs
KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

# GNOME Extensions
# add Clipboard Indicator
# https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator

# add Edit Desktop Files
# https://github.com/Dannflower/edit-desktop-files
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/editdesktopfiles@dannflower/schemas

# add GJS OSK
# https://github.com/Vishram1123/gjs-osk

# add Just Perfection
# https://gitlab.gnome.org/jrahmatzadeh/just-perfection

# add Screen Rotate
# https://github.com/shyzus/gnome-shell-extension-screen-autorotate

# add Weather or Not
# https://gitlab.gnome.org/somepaulo/weather-or-not
mv /usr/share/gnome-shell/extensions/weatherornot@somepaulo.github.io/weatherornot@somepaulo.github.io/* /usr/share/gnome-shell/extensions/weatherornot@somepaulo.github.io/
rm -rf /usr/share/gnome-shell/extensions/weatherornot@somepaulo.github.io-extension/weatherornot@somepaulo.github.io/
rm -f /usr/share/gnome-shell/extensions/weatherornot@somepaulo.github.io-extension.zip
glib-compile-schemas --strict /usr/share/gnome-shell/extensions/weatherornot@somepaulo.github.io/schemas

# Recompile grand schema
rm /usr/share/glib-2.0/schemas/gschemas.compiled
glib-compile-schemas /usr/share/glib-2.0/schemas

# Install additional fedora packages
ADDITIONAL_FEDORA_PACKAGES=(
    chromium # for WebUSB
    feedbackd # for gnome-calls
    firefox # as RPM for GSConnect
    gdb
    gnome-network-displays
    gnome-shell-extension-appindicator
    gnome-shell-extension-apps-menu
    gnome-shell-extension-auto-move-windows
    gnome-shell-extension-caffeine
    gnome-shell-extension-dash-to-dock
    gnome-shell-extension-drive-menu
    gnome-shell-extension-gsconnect
    gnome-shell-extension-launch-new-instance
    gnome-shell-extension-light-style
    gnome-shell-extension-native-window-placement
    gnome-shell-extension-places-menu
    gnome-shell-extension-screenshot-window-sizer
    gnome-shell-extension-status-icons
    gnome-shell-extension-system-monitor
    gnome-shell-extension-user-theme
    gnome-shell-extension-window-list
    gnome-shell-extension-windowsNavigator
    gnome-shell-extension-workspace-indicator
    libcamera-qcam
    nextcloud-client-nautilus
    pmbootstrap
    v4l-utils
    wireshark
)

dnf -y install --skip-unavailable \
    "${ADDITIONAL_FEDORA_PACKAGES[@]}"

# feedbackd-0.8.6-3.fc43
dnf -y upgrade --repo=updates-testing --refresh --advisory=FEDORA-2025-147f8170eb

# Cleanup
dnf clean all

find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find /var/cache/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
