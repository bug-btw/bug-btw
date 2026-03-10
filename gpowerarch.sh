#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo bash "$0" "$@"

SELF="$(realpath "$0")"
SERVICE_FILE="/etc/systemd/system/gpower.service"

if [ ! -f "$SERVICE_FILE" ]; then
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Gpower Performance Mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=$SELF
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable gpower.service
fi

for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance > "$gov"
done

for epb in /sys/devices/system/cpu/cpu*/power/energy_perf_bias; do
    [ -f "$epb" ] && echo 0 > "$epb" || true
done

[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ] && echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
[ -f /sys/devices/system/cpu/intel_pstate/min_perf_pct ] && echo 100 > /sys/devices/system/cpu/intel_pstate/min_perf_pct

for card in /sys/class/drm/card*/gt_min_freq_mhz; do
    [ -f "$card" ] || continue
    max=$(cat "${card/gt_min_freq_mhz/gt_max_freq_mhz}" 2>/dev/null)
    [ -n "$max" ] && echo "$max" > "$card"
done

[ -f /sys/class/drm/card0/device/power_dpm_force_performance_level ] && echo high > /sys/class/drm/card0/device/power_dpm_force_performance_level

echo 1500 > /proc/sys/vm/dirty_writeback_centisecs
echo 10 > /proc/sys/vm/swappiness
echo 1 > /proc/sys/vm/dirty_ratio
echo 50 > /proc/sys/vm/dirty_background_ratio
echo 0 > /proc/sys/kernel/nmi_watchdog

for pci in /sys/bus/pci/devices/*/power/control; do
    [ -f "$pci" ] && echo on > "$pci" || true
done

for usb in /sys/bus/usb/devices/*/power/control; do
    [ -f "$usb" ] && echo on > "$usb" || true
done

[ -f /sys/kernel/mm/transparent_hugepage/enabled ] && echo always > /sys/kernel/mm/transparent_hugepage/enabled
[ -f /sys/kernel/mm/transparent_hugepage/defrag ] && echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag

if command -v scx_lavd &>/dev/null; then
    pkill -f scx_ 2>/dev/null || true
    sleep 0.3
    scx_lavd --performance &
fi

exit 0
