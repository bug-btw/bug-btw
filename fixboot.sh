#!/usr/bin/env bash
sudo dnf update --refresh
sudo dnf autoremove
rm -rf ~/.cache/plasmashell*
rm -rf ~/.cache/krunner/
rm -rf ~/.cache/org.kde.dirmodel-qml.kcache
rm -rf ~/.cache/kioexec/
rm -rf ~/.cache/ksycoca5*
sudo dnf reinstall -y $(dnf list installed | grep -E 'plasma|kwin|kde|kf5|kf6' | awk '{print $1}' | tr '\n' ' ')
sudo dnf reinstall -y mesa-dri-drivers kwin-wayland sddm plasma-desktop
sudo grubby --update-kernel=ALL --args="i915.enable_psr=0 i915.enable_dc=0 pcie_aspm=off i915.enable_guc=0"
sudo dracut -f --regenerate-all
reboot
