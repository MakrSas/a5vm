#!/bin/bash
#
# Загружает iPhoneOS6.1.sdk и печатает путь к нему в $GITHUB_ENV (в CI) и на
# stdout.
#
# Современные SDK не подходят принципиально, а не из-за придирчивости: начиная
# примерно с iOS 11 Apple убрала armv7-срезы из стабов libSystem, так что
# слинковать 32-битный бинарник против них невозможно.  Нужен SDK той эпохи, и
# 6.1 — ровно версия целевого устройства, поэтому в него физически нельзя
# случайно позвать API, которого на iPhone 4S не окажется.
#

set -euo pipefail

DEST=${1:-"${RUNNER_TEMP:-/tmp}/iphone-sdk"}
BASE="https://raw.githubusercontent.com/Sn0wCooder/theos-sdks/master/iPhoneOS6.1.sdk"

if SDK=$(find "$DEST" -type d -name 'iPhoneOS6.1.sdk' -print -quit 2>/dev/null) \
   && [ -n "$SDK" ]; then
    echo "$SDK"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Архив в репозитории разрезан на три части по 90 МБ — ограничение на размер
# файла в git, а не что-то осмысленное; склеиваем обратно.
for part in 001 002 003; do
    curl --fail --location --retry 3 --silent --show-error \
        "$BASE/iPhoneOS6.1.sdk.zip.$part" -o "$TMP/part.$part"
done
cat "$TMP"/part.* > "$TMP/sdk.zip"

mkdir -p "$DEST"
unzip -q "$TMP/sdk.zip" -d "$DEST"

SDK=$(find "$DEST" -type d -name 'iPhoneOS6.1.sdk' -print -quit)
if [ -z "$SDK" ]; then
    echo "iPhoneOS6.1.sdk not found in downloaded archive" >&2
    exit 1
fi

# Проверяем сразу, а не в момент падения линковки где-то в середине сборки
# QEMU: без armv7-среза в libSystem дальше идти бессмысленно.
if [ ! -e "$SDK/usr/lib/libSystem.dylib" ] && [ ! -e "$SDK/usr/lib/libSystem.B.dylib" ]; then
    echo "SDK at $SDK has no libSystem — unusable" >&2
    exit 1
fi

echo "$SDK"
