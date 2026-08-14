#!/bin/bash
#
# Сборка libqemu-system-i386.dylib под armv7/iOS 6.
#
# На выходе — build/qemu/libqemu-system-i386.dylib и каталог pc-bios.
# Приложение НЕ линкуется с этой библиотекой, а грузит её через dlopen
# (см. A5QemuRunner), поэтому единственное, что от неё требуется, —
# экспортировать функции a5_qemu_* из bridge/a5_qemu.c и не тянуть ничего
# снаружи бандла.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ios-env.sh"

# Форк UTM с поддержкой iOS: в апстримном QEMU нет ни --enable-shared-lib,
# ни ветки targetos=iOS.  Коммит зафиксирован, чтобы сборка была
# воспроизводимой.
QEMU_REPO="https://github.com/utmapp/qemu.git"
QEMU_COMMIT="2fb97f4f833a6442d2b62ca6bdbf80b3e386b133"

QEMU_SRC="$A5_WORK/qemu"
QEMU_BUILD="$A5_WORK/qemu-build"
OUT_DIR=${OUT_DIR:-"$A5_ROOT/build/qemu"}

mkdir -p "$A5_WORK" "$OUT_DIR"

# ------------------------------------------------------------------ исходники
if [ ! -d "$QEMU_SRC/.git" ]; then
    a5_log "загрузка QEMU $QEMU_COMMIT"
    rm -rf "$QEMU_SRC"
    mkdir -p "$QEMU_SRC"
    (
        cd "$QEMU_SRC"
        git init -q
        git remote add origin "$QEMU_REPO"
        git fetch -q --depth 1 origin "$QEMU_COMMIT"
        git checkout -q FETCH_HEAD
    )
fi

# Из полутора десятков сабмодулей нужен ровно один: ui/keycodemapdb, из
# которого генерируются таблицы преобразования кодов клавиш (ui/input-keymap-*.c).
# Всё остальное (roms/*, capstone, slirp, dtc, libucontext) либо отключено
# ключами configure, либо не участвует в сборке i386-softmmu.
if [ ! -f "$QEMU_SRC/ui/keycodemapdb/data/keymaps.csv" ]; then
    a5_log "получение ui/keycodemapdb"
    (cd "$QEMU_SRC" && git submodule update --init ui/keycodemapdb)
fi

# ------------------------------------------------------------------ правки
# Все изменения исходников QEMU собраны в одном месте, с объяснением каждого.
a5_log "правки исходников"
python3 "$SCRIPT_DIR/patch-qemu.py" "$QEMU_SRC"

# ------------------------------------------------------------------ мост
#
# Мост компилируется ВНУТРИ дерева QEMU, а не отдельно: только так он видит
# настоящие ui/console.h и ui/input.h и не вынуждает приложение вручную
# повторять layout внутренних структур QEMU.
#
a5_log "установка моста в ui/"
cp "$A5_ROOT/bridge/a5_qemu.c" "$QEMU_SRC/ui/a5_qemu.c"
cp "$A5_ROOT/bridge/a5_qemu.h" "$QEMU_SRC/ui/a5_qemu.h"
if ! grep -q 'a5_qemu.o' "$QEMU_SRC/ui/Makefile.objs"; then
    echo 'common-obj-y += a5_qemu.o' >> "$QEMU_SRC/ui/Makefile.objs"
fi

# ------------------------------------------------------------------ флаги
#
# CFLAGS и LDFLAGS обязаны нести ОДИН И ТОТ ЖЕ -target: configure склеивает
# их в одну команду clang для своих проверок, а из нескольких -target в
# командной строке побеждает последний.  Разъехавшись, они молча заставят
# проверки компилироваться под другой таргет, чем настоящая сборка.
#
QEMU_CFLAGS="$A5_QEMU_BASE_CFLAGS -fPIC -O2 $A5_LEGACY_C_FLAGS"
QEMU_CFLAGS="$QEMU_CFLAGS -include $SCRIPT_DIR/compat/ios6-compat.h"
QEMU_CFLAGS="$QEMU_CFLAGS -I$A5_DEPS/include"

#
# Apple-специфичные имена математических функций: для этого таргета компилятор
# распознаёт pow(10, x) и стоящие рядом sin(x)/cos(x) (ровно так написана
# эмуляция FSINCOS в target/i386/fpu_helper.c) и переписывает их в ___exp10 и
# ___sincos_stret — символы с другим ABI, появившиеся уже после этого SDK.
# Литерального вызова sincos() в исходниках нет, поэтому -fno-builtin-sincos
# сам по себе ничего не даёт: слияние идёт по отдельно распознанным sin и cos.
#
QEMU_CFLAGS="$QEMU_CFLAGS -fno-builtin-sin -fno-builtin-cos -fno-builtin-sincos"
QEMU_CFLAGS="$QEMU_CFLAGS -fno-builtin-pow -fno-builtin-exp10"

QEMU_LDFLAGS="$A5_QEMU_BASE_CFLAGS -L$A5_DEPS/lib"

#
# __emutls_get_address и __clear_cache берутся из compiler-rt, а не пишутся
# руками.
#
# Своя реализация emutls тут была и работала правильно (проверено на
# устройстве отдельным тестом), но брала мьютекс на КАЖДОЕ обращение к
# __thread-переменной. Для QEMU это смертельно: tb_exec_lock()/unlock()
# трогают tcg_ctx вокруг каждого исполнения блока трансляции, current_cpu и
# RCU — ещё чаще. В compiler-rt тот же вызов в разы дешевле: атомарное
# чтение индекса и pthread_getspecific, без блокировок на горячем пути.
#
# Архив подключается явно, хотя clang обычно делает это сам: если срез
# armv7 когда-нибудь исчезнет из Xcode, отказ будет сразу на линковке и с
# понятной причиной, а не в виде загадочного поведения на устройстве.
#
COMPILER_RT_LIB="$(find "$(dirname "$A5_CC")/../lib/clang" -name 'libclang_rt.ios.a' -print -quit 2>/dev/null || true)"
if [ -z "$COMPILER_RT_LIB" ]; then
    echo "libclang_rt.ios.a не найдена — неоткуда взять __emutls_get_address" >&2
    exit 1
fi
a5_log "compiler-rt: $COMPILER_RT_LIB"
lipo -info "$COMPILER_RT_LIB" 2>&1 | sed 's/^/    /' || true
if ! lipo -info "$COMPILER_RT_LIB" 2>/dev/null | grep -q armv7; then
    echo "в libclang_rt.ios.a нет среза armv7" >&2
    exit 1
fi
QEMU_LDFLAGS="$QEMU_LDFLAGS $COMPILER_RT_LIB"

# __clear_cache в этом срезе compiler-rt всё же не нашёлся (в отличие от
# emutls), поэтому остаётся своим — см. scripts/compat/ios6-compat.c.
a5_log "сборка заглушек рантайма"
"$A5_CC" $QEMU_CFLAGS -c "$SCRIPT_DIR/compat/ios6-compat.c" \
    -o "$A5_WORK/ios6-compat.o"
QEMU_LDFLAGS="$QEMU_LDFLAGS $A5_WORK/ios6-compat.o"

# Отдельная проверка эмулированного TLS — теми же флагами, что и QEMU,
# и с тем же ios6-compat.o.  См. tools/tls-selftest.c.
a5_log "сборка tls-selftest"
"$A5_CC" $QEMU_CFLAGS -o "$OUT_DIR/tls-selftest" \
    "$A5_ROOT/tools/tls-selftest.c" $QEMU_LDFLAGS
xcrun --sdk iphoneos vtool \
    -set-version-min ios "$A5_MIN_VERSION" "$A5_SDK_VERSION" \
    -replace -output "$OUT_DIR/tls-selftest" "$OUT_DIR/tls-selftest"

export PKG_CONFIG_LIBDIR="$A5_DEPS/lib/pkgconfig:$A5_DEPS/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export PKG_CONFIG_SYSROOT_DIR=""

# ------------------------------------------------------------------ configure
rm -rf "$QEMU_BUILD"
mkdir -p "$QEMU_BUILD"

dump_logs_on_failure() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "===== config.log ====="
        tail -n 120 "$QEMU_BUILD/config.log" 2>/dev/null || true
        echo "===== config-host.mak (флаги) ====="
        grep -E '^(CFLAGS|LDFLAGS|QEMU_CFLAGS|QEMU_LDFLAGS|ARCH|CONFIG_IOS)' \
            "$QEMU_BUILD/config-host.mak" 2>/dev/null || true
    fi
    exit "$status"
}
trap dump_logs_on_failure EXIT

#
# A5_TCG_INTERPRETER=1 собирает QEMU с интерпретатором TCG вместо генерации
# нативного кода.  Он в разы медленнее, но не требует ни исполняемой памяти,
# ни согласованности кэшей — то есть служит и запасным вариантом для
# устройств, где ядро не даёт RWX, и способом разделить «сломана генерация
# кода» и «сломано что-то ещё» при разборе неполадок.
#
QEMU_EXTRA_ARGS=""
if [ -n "${A5_TCG_INTERPRETER:-}" ]; then
    a5_log "режим: интерпретатор TCG (без JIT)"
    QEMU_EXTRA_ARGS="--enable-tcg-interpreter"
fi

a5_log "configure"
(
    cd "$QEMU_BUILD"
    CFLAGS="$QEMU_CFLAGS" \
    LDFLAGS="$QEMU_LDFLAGS" \
    "$QEMU_SRC/configure" \
        --cc="$A5_CC" \
        --host-cc="$(xcrun --find clang)" \
        --cpu=arm \
        --target-list=i386-softmmu \
        --enable-shared-lib \
        --disable-werror \
        --disable-pie \
        --with-coroutine=sigaltstack \
        --cxx=a5-no-cxx-compiler \
        --disable-docs --disable-guest-agent --disable-tools \
        --disable-modules --disable-plugins \
        --disable-cocoa --disable-sdl --disable-gtk --disable-curses \
        --disable-vnc --disable-spice --disable-opengl \
        --disable-virtfs --disable-slirp --disable-fdt --disable-capstone \
        --disable-curl --disable-gnutls --disable-nettle --disable-gcrypt \
        --disable-libssh --disable-libxml2 \
        --disable-lzo --disable-snappy --disable-zstd --disable-bzip2 \
        --disable-lzfse --disable-seccomp --disable-cap-ng \
        --disable-kvm --disable-hvf --disable-hax --disable-whpx --disable-xen \
        --disable-rdma --disable-pvrdma --disable-vde --disable-netmap \
        --disable-linux-aio --disable-libnfs --disable-libiscsi \
        --disable-usb-redir --disable-libusb --disable-smartcard \
        --disable-tpm --disable-attr --disable-xfsctl --disable-mpath \
        --disable-libpmem --disable-malloc-trim \
        $QEMU_EXTRA_ARGS \
        --extra-cflags="$QEMU_CFLAGS" \
        --extra-ldflags="$QEMU_LDFLAGS"
)

a5_log "сборка"
make -C "$QEMU_BUILD" -j"$(sysctl -n hw.ncpu)" i386-softmmu/all

trap - EXIT

# ------------------------------------------------------------------ доводка
LIBRARY="$QEMU_BUILD/i386-softmmu/libqemu-system-i386.dylib"
test -f "$LIBRARY"

#
# Линковщик записал в библиотеку деплоймент-таргет iOS 9.0 — он был указан
# только чтобы пройти проверку TLS в компиляторе (см. ios-env.sh).  Если
# оставить как есть, dyld на iPhone 4S откажется грузить библиотеку,
# которая якобы требует iOS 9.  Возвращаем настоящий минимум.
#
#
# Именно -set-version-min, а не -set-build-version: первый записывает
# legacy-команду LC_VERSION_MIN_IPHONEOS, вторая — LC_BUILD_VERSION,
# появившуюся только в 2017 году вместе с SDK iOS 11.  dyld на iOS 6 о
# существовании второй не знает, и полагаться на то, что он аккуратно
# пропустит незнакомую команду загрузки, незачем — тем более что у самого
# приложения там ровно legacy-вариант.
#
a5_log "выставление минимальной версии iOS $A5_MIN_VERSION"
xcrun --sdk iphoneos vtool \
    -set-version-min ios "$A5_MIN_VERSION" "$A5_SDK_VERSION" \
    -replace -output "$LIBRARY" "$LIBRARY"

if ! otool -l "$LIBRARY" | grep -q LC_VERSION_MIN_IPHONEOS; then
    echo "в библиотеке нет LC_VERSION_MIN_IPHONEOS — dyld на iOS 6 её не поймёт" >&2
    otool -l "$LIBRARY" | grep -A4 -E 'LC_BUILD_VERSION|LC_VERSION_MIN' >&2
    exit 1
fi

# configure не передаёт -install_name, поэтому линковщик записал в LC_ID_DYLIB
# абсолютный путь сборочной машины.  Для dlopen по явному пути это не важно,
# но пусть в библиотеке не остаётся путей, которых на устройстве нет.
install_name_tool -id "@executable_path/libqemu-system-i386.dylib" "$LIBRARY"

cp "$LIBRARY" "$OUT_DIR/"
cp "$QEMU_SRC/COPYING" "$OUT_DIR/QEMU-COPYING"

#
# Из pc-bios берётся только то, что может понадобиться машине pc с гостем
# i386.  Целиком каталог весит около 230 МБ, и почти всё это — образы UEFI
# (edk2) и прошивки для совсем других архитектур: SLOF, openbios, u-boot,
# skiboot.  Ни одна из них не может быть загружена в нашей конфигурации, а
# место на телефоне они занимали бы вполне настоящее.
#
rm -rf "$OUT_DIR/pc-bios"
mkdir -p "$OUT_DIR/pc-bios"
for firmware in \
    bios.bin bios-256k.bin \
    vgabios.bin vgabios-cirrus.bin vgabios-stdvga.bin \
    kvmvapic.bin sgabios.bin pvh.bin \
    linuxboot.bin linuxboot_dma.bin multiboot.bin
do
    if [ -f "$QEMU_BUILD/pc-bios/$firmware" ]; then
        cp "$QEMU_BUILD/pc-bios/$firmware" "$OUT_DIR/pc-bios/"
    else
        echo "прошивка $firmware не найдена в сборке" >&2
        exit 1
    fi
done
a5_log "pc-bios: $(du -sh "$OUT_DIR/pc-bios" | cut -f1)"

a5_log "готово"
file "$OUT_DIR/libqemu-system-i386.dylib"

# Ни одной ссылки на пути сборочной машины быть не должно: любая такая
# зависимость означает, что на устройстве dyld не сможет загрузить
# библиотеку — и это единственный класс ошибок, который сборка в принципе
# способна поймать сама, до установки на телефон.
a5_log "зависимости библиотеки"
otool -L "$OUT_DIR/libqemu-system-i386.dylib"
# tail -n +2 отбрасывает первую строку вывода otool — это имя самого файла,
# а оно, разумеется, лежит по пути сборочной машины и иначе всегда совпадает
# с искомым шаблоном.
if otool -L "$OUT_DIR/libqemu-system-i386.dylib" | tail -n +2 |
        grep -qE "$A5_WORK|/Users/|/opt/homebrew|/usr/local/Cellar"; then
    echo "библиотека ссылается на пути сборочной машины — на устройстве не загрузится" >&2
    exit 1
fi

# Мост обязан быть виден снаружи: приложение резолвит эти имена через dlsym.
a5_log "экспортируемые символы моста"
nm -gU "$OUT_DIR/libqemu-system-i386.dylib" | grep '_a5_qemu_' || {
    echo "в библиотеке нет символов a5_qemu_* — мост не попал в сборку" >&2
    exit 1
}
