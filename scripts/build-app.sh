#!/bin/bash
#
# Сборка A5VM.app под armv7/iOS 6.
#
# Компилятор вызывается напрямую, без theos и без Xcode-проекта: бандл
# jailbreak-приложения — это каталог с бинарником и Info.plist, и городить
# ради него систему сборки не за что.  Заодно сборка приложения ничего не
# знает про QEMU: библиотека грузится через dlopen, поэтому линковаться с
# ней не нужно, и этот шаг не зависит от того, собралась ли она.
#
# QEMU_DIR (необязательно) — каталог с результатом scripts/build-qemu.sh.
# Если задан, библиотека и pc-bios кладутся в бандл.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ios-env.sh"

OUT_DIR=${OUT_DIR:-"$A5_ROOT/build/app"}
QEMU_DIR=${QEMU_DIR:-"$A5_ROOT/build/qemu"}
BUNDLE="$OUT_DIR/A5VM.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE"

a5_log "компиляция A5VM"
# -fobjc-arc: для деплоймент-таргета 6.0 clang берёт нативный ARC рантайма
# (он есть с iOS 5) и не требует libarclite, которую из современных Xcode уже
# убрали.  Версия рантайма выводится именно из -miphoneos-version-min, поэтому
# оптимизации вроде objc_alloc, появившиеся позже, сюда не попадают.
"$A5_CC" $A5_BASE_CFLAGS \
    -fobjc-arc \
    -O2 -Wall -Wno-unused-parameter \
    -I "$A5_ROOT/bridge" \
    "$A5_ROOT/app"/*.m \
    -framework UIKit \
    -framework Foundation \
    -framework CoreGraphics \
    -framework QuartzCore \
    -o "$BUNDLE/A5VM"

cp "$A5_ROOT/app/Info.plist" "$BUNDLE/Info.plist"

if [ -f "$A5_ROOT/app/Icon.png" ]; then
    cp "$A5_ROOT/app/Icon.png" "$BUNDLE/"
fi
if [ -f "$A5_ROOT/app/Icon@2x.png" ]; then
    cp "$A5_ROOT/app/Icon@2x.png" "$BUNDLE/"
fi

if [ -f "$QEMU_DIR/libqemu-system-i386.dylib" ]; then
    a5_log "добавление QEMU в бандл"
    cp "$QEMU_DIR/libqemu-system-i386.dylib" "$BUNDLE/"
    cp -R "$QEMU_DIR/pc-bios" "$BUNDLE/pc-bios"
    cp "$QEMU_DIR/QEMU-COPYING" "$BUNDLE/QEMU-COPYING"
else
    a5_log "ВНИМАНИЕ: QEMU не найден в $QEMU_DIR, бандл собран без него"
fi

# Подпись.  На jailbreak-устройстве достаточно фиктивной: ядро с
# отключённой проверкой подписи принимает её, но совсем без подписи
# бинарник всё равно не запустится.
a5_log "подпись"
ldid -S "$BUNDLE/A5VM"
if [ -f "$BUNDLE/libqemu-system-i386.dylib" ]; then
    ldid -S "$BUNDLE/libqemu-system-i386.dylib"
fi

a5_log "готово: $BUNDLE"
file "$BUNDLE/A5VM"
otool -L "$BUNDLE/A5VM" | sed 's/^/    /'

# Приложение не должно быть слинковано с QEMU: оно обязано подниматься даже
# если библиотека повреждена или отсутствует, чтобы показать внятную ошибку,
# а не падать в dyld до main().
if otool -L "$BUNDLE/A5VM" | grep -q 'libqemu-system-i386'; then
    echo "A5VM слинкован с QEMU напрямую — должен грузить её через dlopen" >&2
    exit 1
fi
