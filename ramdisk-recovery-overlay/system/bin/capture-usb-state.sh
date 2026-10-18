#!/system/bin/sh

sleep 12

mounted_metadata=0
if ! grep -q ' /metadata ' /proc/mounts; then
    mount -t ext4 /dev/block/by-name/metadata /metadata || exit 1
    mounted_metadata=1
fi

mkdir -p /metadata/halium-diagnostics || exit 1
{
    date
    for property in \
        ro.boot.usbcontroller \
        persist.sys.usb.config \
        sys.usb.configfs \
        sys.usb.controller \
        sys.usb.config \
        sys.usb.state \
        sys.usb.ffs.ready \
        init.svc.adbd
    do
        printf '%s=' "$property"
        getprop "$property"
    done
    for node in \
        /sys/bus/platform/devices/4e00000.ssusb/mode \
        /sys/bus/platform/devices/4e00000.ssusb/driver \
        /sys/bus/platform/devices/4e00000.dwc3/driver \
        /sys/class/udc/4e00000.dwc3/state \
        /sys/class/udc/4e00000.dwc3/device/../mode \
        /config/usb_gadget/g1/UDC \
        /config/usb_gadget/g1/idVendor \
        /config/usb_gadget/g1/idProduct \
        /config/usb_gadget/g1/configs/b.1/f1
    do
        printf '\n%s\n' "$node"
        if [ -e "$node" ] || [ -L "$node" ]; then
            ls -l "$node"
            [ -f "$node" ] && cat "$node"
        else
            echo missing
        fi
    done
    for node in \
        /proc/device-tree/soc/ssusb@4e00000/status \
        /proc/device-tree/soc/ssusb@4e00000/dwc3@4e00000/status
    do
        printf '\n%s\n' "$node"
        if [ -f "$node" ]; then
            tr -d '\000' < "$node"
            echo
        else
            echo missing
        fi
    done
    echo
    ls -l /sys/class/udc
    echo
    echo "USB-related platform devices"
    ls -l /sys/bus/platform/devices | grep -iE 'dwc3|ssusb|usb'
    echo
    echo "USB-related platform drivers"
    ls -l /sys/bus/platform/drivers | grep -iE 'dwc3|ssusb|usb'
    echo
    echo "Module lists present in the initramfs"
    ls -l /lib/modules/ 2>&1 | head -20
    echo "modules.load.recovery:"
    cat /lib/modules/modules.load.recovery 2>&1 | head -40
    echo
    echo "Loaded modules"
    cat /proc/modules 2>&1 | head -40
    echo "(total: $(wc -l < /proc/modules 2>/dev/null) modules)"
    echo
    echo "Full kernel log"
    dmesg
} > /metadata/halium-diagnostics/usb-state.txt 2>&1
sync

if [ "$mounted_metadata" = 1 ]; then
    umount /metadata
fi
