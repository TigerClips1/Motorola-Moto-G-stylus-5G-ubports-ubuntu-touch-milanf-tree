#!/system/bin/sh

DEST=/tmp/halium-logs
mkdir -p "$DEST" || exit 1
: > "$DEST/copy.log" || exit 1

metadata_mounted_by_script=0
if ! grep -Fq " /metadata " /proc/mounts; then
    mkdir -p /metadata || exit 1
    if mount -t ext4 -o ro,noload /dev/block/by-name/metadata /metadata 2>> "$DEST/copy.log"; then
        metadata_mounted_by_script=1
    else
        echo "Could not mount /dev/block/by-name/metadata" >> "$DEST/copy.log"
    fi
fi

copied=0
for name in halium-initrd.log halium-kmsg.log halium-mounts.log halium-posthandoff-kmsg.log; do
    for source in "/data/$name" "/metadata/halium-diagnostics/$name"; do
        if [ -f "$source" ]; then
            cp -p "$source" "$DEST/$name" || {
                echo "Failed to copy $source" >> "$DEST/copy.log"
                continue
            }
            echo "Copied $source" >> "$DEST/copy.log"
            copied=1
        fi
    done
done

if [ "$copied" -eq 0 ]; then
    echo "No Halium boot logs were found in /data or /metadata/halium-diagnostics" >> "$DEST/copy.log"
fi

if [ "$metadata_mounted_by_script" -eq 1 ]; then
    umount /metadata || echo "Could not unmount /metadata after copying logs" >> "$DEST/copy.log"
fi

sync
