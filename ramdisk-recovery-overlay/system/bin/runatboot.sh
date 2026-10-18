#!/system/bin/sh
#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP Device Tree Generator
# Copyright (C) 2019-Present A-Team Digital Solutions
# Copyright (C) 2024 sosRR
#

log() {
    echo "milanf runatboot: $*"
}

setenforce 0 || log "could not set SELinux permissive"

MODULE_DIR=/lib/modules
if [ ! -d /sys/module/nova_0flash_mmi ]; then
    if [ -x /system/bin/modprobe ] && [ -r "$MODULE_DIR/nova_0flash_mmi.ko" ]; then
        /system/bin/modprobe -d "$MODULE_DIR" nova_0flash_mmi ||
            log "could not load nova_0flash_mmi from $MODULE_DIR"
    else
        log "nova_0flash_mmi is not loaded and is unavailable in $MODULE_DIR"
    fi
fi

PANEL_SUPPLIER_PATH=/sys/devices/platform/soc/5e00000.qcom,mdss_mdp/drm/card0/card0-DSI-1/panelSupplier
TOUCH_REFLASH=/sys/class/touchscreen/primary/forcereflash
TOUCH_FIRMWARE=/sys/class/touchscreen/primary/doreflash

if [ -r "$PANEL_SUPPLIER_PATH" ]; then
    PANEL_SUPPLIER=$(cat "$PANEL_SUPPLIER_PATH")
    case "$PANEL_SUPPLIER" in
        csot) TOUCH_FW=csot_novatek_ts_fw.bin ;;
        tm) TOUCH_FW=tm_novatek_ts_fw.bin ;;
        tianma) TOUCH_FW=tianma_novatek_ts_fw.bin ;;
        *) TOUCH_FW= ;;
    esac

    if [ -n "$TOUCH_FW" ] && [ -w "$TOUCH_REFLASH" ] && [ -w "$TOUCH_FIRMWARE" ]; then
        if printf '1\n' > "$TOUCH_REFLASH"; then
            if printf '%s\n' "$TOUCH_FW" > "$TOUCH_FIRMWARE"; then
                log "requested touchscreen firmware $TOUCH_FW"
            else
                log "touchscreen firmware update failed for $TOUCH_FW"
            fi
            printf '0\n' > "$TOUCH_REFLASH" ||
                log "could not clear touchscreen force-reflash flag"
        else
            log "could not enable touchscreen force-reflash"
        fi
    elif [ -z "$TOUCH_FW" ]; then
        log "unsupported touchscreen panel supplier: $PANEL_SUPPLIER"
    else
        log "touchscreen firmware-update sysfs controls are unavailable; relying on kernel firmware loading"
    fi
else
    log "panel supplier is unavailable; skipping optional touchscreen reflash"
fi

SLOT=$(getprop ro.boot.slot_suffix)
case "$SLOT" in
    _a|_b) ;;
    *)
        log "invalid or missing slot suffix: $SLOT"
        exit 1
        ;;
esac

MODEM_PARTITION="/dev/block/bootdevice/by-name/modem$SLOT"
if [ ! -e "$MODEM_PARTITION" ]; then
    log "modem partition is missing: $MODEM_PARTITION"
    exit 1
fi

mkdir -p /firmware || {
    log "could not create /firmware"
    exit 1
}

if ! grep -q ' /firmware ' /proc/mounts; then
    mount -o ro "$MODEM_PARTITION" /firmware || {
        log "could not mount $MODEM_PARTITION at /firmware"
        exit 1
    }
fi

if [ ! -d /firmware/image ]; then
    log "modem firmware directory is missing: /firmware/image"
    exit 1
fi

FIRMWARE_PATH=/sys/module/firmware_class/parameters/path
if [ -w "$FIRMWARE_PATH" ]; then
    printf '/firmware/image\n' > "$FIRMWARE_PATH" || {
        log "could not set the kernel firmware search path"
        exit 1
    }
else
    log "kernel firmware path control is unavailable; relying on ueventd firmware directories"
fi

FORCE_SYSFS_FALLBACK=/proc/sys/kernel/firmware_config/force_sysfs_fallback
if [ -w "$FORCE_SYSFS_FALLBACK" ]; then
    printf '1\n' > "$FORCE_SYSFS_FALLBACK" || {
        log "could not enable firmware sysfs fallback"
        exit 1
    }
fi

ADSP_BOOT=/sys/kernel/boot_adsp/boot
if [ ! -w "$ADSP_BOOT" ]; then
    log "ADSP boot control is unavailable: $ADSP_BOOT"
    exit 1
fi

printf '1\n' > "$ADSP_BOOT" || {
    log "could not start ADSP firmware loading"
    exit 1
}

log "ADSP firmware loading started from modem slot $SLOT"
