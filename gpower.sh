#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance | tee "$cpu" > /dev/null
done

echo 1500 | tee /proc/sys/vm/dirty_writeback_centisecs > /dev/null
echo 10   | tee /proc/sys/vm/swappiness > /dev/null
echo 1    | tee /proc/sys/kernel/nmi_watchdog > /dev/null

if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
    echo 0 | tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
fi

if [ -f /sys/class/drm/card0/device/power_dpm_force_performance_level ]; then
    echo high | tee /sys/class/drm/card0/device/power_dpm_force_performance_level > /dev/null
fi

for card in /sys/class/drm/card*/gt_min_freq_mhz; do
    max=$(cat "${card/gt_min_freq_mhz/gt_max_freq_mhz}" 2>/dev/null)
    [ -n "$max" ] && echo "$max" | tee "$card" > /dev/null
done

echo on | tee /sys/bus/pci/devices/*/power/control > /dev/null 2>&1 || true
