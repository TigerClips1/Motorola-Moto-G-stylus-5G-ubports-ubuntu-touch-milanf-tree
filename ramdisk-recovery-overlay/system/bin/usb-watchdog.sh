#!/system/bin/sh
#
# USB cable watchdog for the UBports recovery.
#
# The DWC3 glue driver normally learns that a cable was plugged in from the
# extcon devices it is wired to, but on this kernel the extcon states are never
# driven (mmi_discrete_charger never sets use_extcon) and the vbus_active flag
# is sticky, so in recovery the USB link does not come back after a cable
# re-plug: `mode` keeps reporting "peripheral" and the DRD state machine is
# never re-run.
#
# The glue exposes its vbus state through /sys/.../4e00000.ssusb/mode, which is
# the interface vendor userspace uses to announce cable events.  This watchdog
# mirrors the charger's cable state into that node and, when the link is up but
# the host never enumerated, re-arms functionfs and forces a fresh attach.
#
# Everything is logged to the metadata partition, because losing the USB link
# also takes away the only way to read a log.
#

META_DEV=/dev/block/by-name/metadata
META_MNT=/tmp/usbmon-meta
BUF=/tmp/usb-monitor.log
SAMPLE_INTERVAL=1
MAX_SAMPLES=3600
PERSIST_RETRY=15
LOG_MAX_BYTES=2000000
SSUSB=/sys/bus/platform/devices/4e00000.ssusb
MODE=$SSUSB/mode
UDC=/sys/class/udc/4e00000.dwc3
HEAL_AFTER=3
HEAL_INTERVAL=12

PERSIST_DIR=""
PERSIST_LOG=""
flushed=0

log() {
    echo "$*" >> "$BUF"
}

# ---------------------------------------------------------------------------
# Persistent copy of the log, best effort, never blocking.
# ---------------------------------------------------------------------------
try_persist() {
    local mnt

    if [ -z "$PERSIST_DIR" ]; then
        mnt=$(grep -F " $META_DEV " /proc/mounts 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "$mnt" ]; then
            PERSIST_DIR=$mnt/halium-diagnostics
        else
            mkdir -p "$META_MNT" 2>/dev/null
            if timeout 5 mount -t ext4 -o rw "$META_DEV" "$META_MNT" 2>/dev/null; then
                PERSIST_DIR=$META_MNT/halium-diagnostics
            fi
        fi
        if [ -n "$PERSIST_DIR" ] && ! mkdir -p "$PERSIST_DIR" 2>/dev/null; then
            PERSIST_DIR=""
        fi
        [ -n "$PERSIST_DIR" ] && log "=== persistent log at $PERSIST_DIR ==="
    fi

    [ -n "$PERSIST_DIR" ] || return 1

    PERSIST_LOG=$PERSIST_DIR/usb-monitor.log
    tail -c +$((flushed + 1)) "$BUF" >> "$PERSIST_LOG" 2>/dev/null || return 1
    flushed=$(wc -c < "$BUF" 2>/dev/null)
    sync
    return 0
}

prune_buf() {
    local size
    size=$(wc -c < "$BUF" 2>/dev/null)
    [ -n "$size" ] || return 0
    [ "$size" -lt "$LOG_MAX_BYTES" ] && return 0
    tail -n 5000 "$BUF" > "$BUF.tmp" 2>/dev/null && mv "$BUF.tmp" "$BUF"
    flushed=0
    [ -n "$PERSIST_LOG" ] && : > "$PERSIST_LOG"
    log "=== log pruned at $(date) ==="
}

udc_state() {
    cat $UDC/state 2>/dev/null
}

glue_mode() {
    cat $MODE 2>/dev/null
}

# The charger power supply tracks the physical cable reliably, unlike the glue.
cable_present() {
    local v
    for f in /sys/class/power_supply/charger/online \
             /sys/class/power_supply/usb/online; do
        v=$(cat "$f" 2>/dev/null)
        [ -n "$v" ] && { echo "$v"; return; }
    done
    echo "?"
}

wr() {
    local out
    out=$( { printf '%s' "$1" > "$2"; } 2>&1 )
    if [ $? -ne 0 ]; then
        log "HEAL: writing '$1' to $2 failed: $out"
        return 1
    fi
    return 0
}

snapshot_full() {
    local u p e

    echo "--- sample=$1 uptime=$(cut -d' ' -f1 /proc/uptime) adbd=$(getprop init.svc.adbd) cable=$(cable_present)"
    echo "props config=$(getprop sys.usb.config) state=$(getprop sys.usb.state) ffs.ready=$(getprop sys.usb.ffs.ready) controller=$(getprop sys.usb.controller)"
    echo "glue mode=$(glue_mode) driver=$(basename $(readlink -f $SSUSB/driver 2>/dev/null) 2>/dev/null)"
    echo "gadget UDC='$(cat /config/usb_gadget/g1/UDC 2>/dev/null)' idVendor=$(cat /config/usb_gadget/g1/idVendor 2>/dev/null) idProduct=$(cat /config/usb_gadget/g1/idProduct 2>/dev/null) f1=$(readlink /config/usb_gadget/g1/configs/b.1/f1 2>/dev/null)"

    for u in /sys/class/udc/*; do
        [ -e "$u" ] || continue
        echo "udc=$(basename $u) state=$(cat $u/state 2>/dev/null) speed=$(cat $u/current_speed 2>/dev/null) maxspeed=$(cat $u/maximum_speed 2>/dev/null)"
    done

    for p in /sys/class/power_supply/*; do
        [ -e "$p" ] || continue
        echo "psy=$(basename $p) online=$(cat $p/online 2>/dev/null) present=$(cat $p/present 2>/dev/null) usb_type=$(cat $p/usb_type 2>/dev/null) status=$(cat $p/status 2>/dev/null)"
    done

    for e in /sys/class/extcon/*; do
        [ -e "$e" ] || continue
        echo "extcon=$(basename $e) name=$(cat $e/name 2>/dev/null) state=$(cat $e/state 2>/dev/null | tr '\n' ' ')"
    done
}

# Everything the sampling records, collapsed into one line for change detection.
fingerprint() {
    {
        echo "$(getprop sys.usb.config) $(getprop sys.usb.state) $(getprop sys.usb.ffs.ready) $(getprop init.svc.adbd)"
        cable_present
        glue_mode
        cat /config/usb_gadget/g1/UDC 2>/dev/null
        cat /sys/class/udc/*/state 2>/dev/null
        cat /sys/class/udc/*/current_speed 2>/dev/null
        cat /sys/class/power_supply/*/online 2>/dev/null
    } 2>/dev/null | tr '\n' '|'
}

# The ipa_fws retry storm floods the 256 KiB ring buffer within seconds, so a
# plain tail would miss the USB messages entirely.
usb_dmesg() {
    dmesg 2>/dev/null | grep -v -E "ipa_fws|msm_gsi|subsys-pil-tz" |
        grep -i -E "usb|dwc3|gadget|udc|configfs|init: .*(usb|UDC)|charger" | tail -n 60 |
        sed 's/^/  /'
}

log "=== usb-watchdog start $(date) slot=$(getprop ro.boot.slot_suffix) ==="
log "kernel=$(cat /proc/version)"
try_persist

prev=""
lost=0
last_heal=-1000
i=0
while [ $i -lt $MAX_SAMPLES ]; do
    i=$((i + 1))
    cur="$(fingerprint)"

    if [ "$cur" != "$prev" ]; then
        log "=== STATE CHANGE at sample $i new='$cur' ==="
        snapshot_full "$i" >> "$BUF" 2>&1
        log "usb-dmesg-on-change:"
        usb_dmesg >> "$BUF"
        prev="$cur"
        try_persist
    fi

    present=$(cable_present)
    mode=$(glue_mode)
    state=$(udc_state)

    if [ "$(getprop sys.usb.config)" = "adb" ]; then
        # 1. Mirror the cable state into the glue; nothing else does it here.
        if [ "$present" = "1" ] && [ "$mode" = "none" ]; then
            log "SYNC: cable present but glue mode=none, asserting peripheral"
            wr peripheral $MODE
            sleep 1
            try_persist
        elif [ "$present" = "0" ] && [ "$mode" != "none" ]; then
            log "SYNC: cable absent but glue mode=$mode, clearing it"
            wr none $MODE
            sleep 1
            try_persist
        fi

        # 2. Cable in, glue in device mode, but the host never enumerated:
        #    re-arm functionfs and force a fresh attach.
        if [ "$present" = "1" ] && [ "$(glue_mode)" = "peripheral" ]; then
            if [ "$state" = "configured" ]; then
                lost=0
            else
                lost=$((lost + 1))
                if [ "$lost" -ge $HEAL_AFTER ] && [ $((i - last_heal)) -ge $HEAL_INTERVAL ]; then
                    log "HEAL: link down for ${lost}s (udc state='$state'); re-arming and re-attaching"
                    if [ "$(getprop init.svc.adbd)" != "running" ]; then
                        setprop ctl.start adbd
                    else
                        setprop ctl.restart adbd
                    fi
                    sleep 1
                    wr none $MODE
                    sleep 1
                    wr peripheral $MODE
                    sleep 2
                    log "HEAL: after re-attach udc state='$(udc_state)'"
                    usb_dmesg >> "$BUF"
                    last_heal=$i
                    lost=0
                    try_persist
                fi
            fi
        else
            lost=0
        fi
    fi

    [ $((i % PERSIST_RETRY)) -eq 0 ] && try_persist
    [ $((i % 60)) -eq 0 ] && prune_buf
    sleep $SAMPLE_INTERVAL
done

log "=== usb-watchdog stop $(date) ==="
try_persist
