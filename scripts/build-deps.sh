#!/bin/bash
#
# Кросс-сборка зависимостей QEMU под armv7/iOS 6.
#
# Всё собирается ТОЛЬКО статически.  Это не вкусовщина: динамические
# библиотеки записали бы в libqemu-system-i386.dylib абсолютные пути этой
# сборочной машины, которых на телефоне нет, и dyld отказался бы грузить
# библиотеку вовсе.  Статика гарантирует, что в бандл нужно положить ровно
# один файл, и он ни на что снаружи не ссылается.
#

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios-env.sh"

LIBFFI_VERSION=3.3
PCRE2_VERSION=10.42
GLIB_VERSION=2.76.6
GLIB_SERIES=2.76
PIXMAN_VERSION=0.40.0

mkdir -p "$A5_SRC" "$A5_DEPS/lib/pkgconfig"

export CC="$A5_CC"
export CXX="$A5_CC"
export AR="$A5_AR"
export RANLIB="$A5_RANLIB"
export STRIP="$A5_STRIP"
export CFLAGS="$A5_BASE_CFLAGS -fPIC -O2 $A5_LEGACY_C_FLAGS"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$A5_BASE_CFLAGS"
export CPPFLAGS="-I$A5_DEPS/include"

# pkg-config должен видеть ТОЛЬКО наши кросс-собранные пакеты.  Без
# PKG_CONFIG_LIBDIR он подмешает пакеты хоста (macOS/Homebrew, x86_64 или
# arm64), и сборка упадёт уже на линковке, где причина совсем не очевидна.
export PKG_CONFIG_LIBDIR="$A5_DEPS/lib/pkgconfig:$A5_DEPS/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export PKG_CONFIG_SYSROOT_DIR=""

fetch() {
    local url="$1" archive="$2"
    if [ ! -f "$A5_SRC/$archive" ]; then
        a5_log "загрузка $archive"
        curl --fail --location --retry 3 --silent --show-error "$url" \
            -o "$A5_SRC/$archive.part"
        mv "$A5_SRC/$archive.part" "$A5_SRC/$archive"
    fi
    if [ ! -d "$A5_SRC/$3" ]; then
        tar -xf "$A5_SRC/$archive" -C "$A5_SRC"
    fi
}

# Маркеры готовности лежат рядом с результатом, а не в каталоге исходников:
# кэшируется в CI только work/deps и work/stamps, а распакованные архивы —
# нет, они восстанавливаются дешевле, чем занимают место в кэше.
A5_STAMPS="$A5_WORK/stamps"
mkdir -p "$A5_STAMPS"
built() { [ -f "$A5_STAMPS/$1" ]; }
mark_built() { touch "$A5_STAMPS/$1"; }

# ---------------------------------------------------------------- libffi
# Нужен gobject для замыканий; сам QEMU его не использует напрямую.
if ! built "libffi-$LIBFFI_VERSION"; then
    fetch "https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/libffi-$LIBFFI_VERSION.tar.gz" \
        "libffi-$LIBFFI_VERSION.tar.gz" "libffi-$LIBFFI_VERSION"
    a5_log "сборка libffi"
    (
        cd "$A5_SRC/libffi-$LIBFFI_VERSION"
        ./configure --host=arm-apple-darwin --prefix="$A5_DEPS" \
            --disable-shared --enable-static --disable-dependency-tracking \
            --disable-docs
        make -j"$(sysctl -n hw.ncpu)"
        make install
    )
    mark_built "libffi-$LIBFFI_VERSION"
fi

# ---------------------------------------------------------------- pcre2
# glib 2.74+ ищет именно pcre2 (раньше был встроенный pcre1).
if ! built "pcre2-$PCRE2_VERSION"; then
    fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz" \
        "pcre2-$PCRE2_VERSION.tar.gz" "pcre2-$PCRE2_VERSION"
    a5_log "сборка pcre2"
    (
        cd "$A5_SRC/pcre2-$PCRE2_VERSION"
        # JIT в pcre2 отключён намеренно: собственный генератор кода здесь
        # не нужен, а на iOS он лишь добавил бы ещё одну сущность, которой
        # требуется исполняемая память.
        ./configure --host=arm-apple-darwin --prefix="$A5_DEPS" \
            --disable-shared --enable-static --disable-dependency-tracking \
            --disable-pcre2grep --disable-pcre2test --disable-jit
        make -j"$(sysctl -n hw.ncpu)"
        make install
    )
    mark_built "pcre2-$PCRE2_VERSION"
fi

# ---------------------------------------------------------------- glib
if ! built "glib-$GLIB_VERSION"; then
    fetch "https://download.gnome.org/sources/glib/$GLIB_SERIES/glib-$GLIB_VERSION.tar.xz" \
        "glib-$GLIB_VERSION.tar.xz" "glib-$GLIB_VERSION"

    # gspawn.c на Apple тянет <libproc.h>/<sys/proc_info.h> ради перечисления
    # открытых дескрипторов.  В iPhoneOS6.1.sdk этих заголовков нет, а QEMU
    # на iOS всё равно ничего не запускает через g_spawn.  Прячем блок за
    # макросом, который выставляется только для этой сборки.
    GSPAWN="$A5_SRC/glib-$GLIB_VERSION/glib/gspawn.c"
    if grep -q '#include <libproc.h>' "$GSPAWN"; then
        perl -0pi -e 's/#ifdef __APPLE__\n#include <libproc\.h>/#if defined(__APPLE__) \&\& !defined(A5_IOS_BUILD)\n#include <libproc.h>/' "$GSPAWN"
        perl -0pi -e 's/#if defined\(__APPLE__\)\n(\s*\/\* proc_pidinfo)/#if defined(__APPLE__) \&\& !defined(A5_IOS_BUILD)\n$1/' "$GSPAWN"
        a5_log "gspawn.c: блок libproc скрыт под A5_IOS_BUILD"
    else
        a5_log "gspawn.c: блок libproc не найден, патч не нужен"
    fi

    cat > "$A5_WORK/glib-cross.ini" <<EOF
[binaries]
c = '$A5_CC'
cpp = '$A5_CC'
ar = '$A5_AR'
ranlib = '$A5_RANLIB'
strip = '$A5_STRIP'
pkg-config = '$(command -v pkg-config)'

[built-in options]
c_args = ['-target', '$A5_TARGET', '-arch', '$A5_ARCH', '-isysroot', '$A5_SDKROOT', '-miphoneos-version-min=$A5_MIN_VERSION', '-fPIC', '-O2', '-I$A5_DEPS/include', '-DA5_IOS_BUILD', '-Wno-implicit-function-declaration', '-Wno-implicit-int', '-Wno-int-conversion', '-Wno-incompatible-pointer-types']
c_link_args = ['-target', '$A5_TARGET', '-arch', '$A5_ARCH', '-isysroot', '$A5_SDKROOT', '-miphoneos-version-min=$A5_MIN_VERSION', '-L$A5_DEPS/lib']

[host_machine]
system = 'darwin'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
EOF

    a5_log "сборка glib"
    (
        cd "$A5_SRC/glib-$GLIB_VERSION"
        rm -rf build
        # nls=disabled убирает gettext: иначе meson полез бы качать
        # subproject proxy-libintl, добавляя сетевую зависимость и ещё одну
        # библиотеку, которую пришлось бы делать статической.
        meson setup build --cross-file "$A5_WORK/glib-cross.ini" \
            --prefix="$A5_DEPS" \
            --default-library=static \
            -Dtests=false -Dinstalled_tests=false \
            -Dnls=disabled -Dman=false -Dgtk_doc=false \
            -Dglib_assert=false -Dglib_checks=false \
            -Dlibmount=disabled -Dselinux=disabled -Dxattr=false \
            -Ddtrace=false -Dsystemtap=false
        meson compile -C build
        meson install -C build
    )
    mark_built "glib-$GLIB_VERSION"
fi

# ---------------------------------------------------------------- pixman
if ! built "pixman-$PIXMAN_VERSION"; then
    fetch "https://www.cairographics.org/releases/pixman-$PIXMAN_VERSION.tar.gz" \
        "pixman-$PIXMAN_VERSION.tar.gz" "pixman-$PIXMAN_VERSION"
    a5_log "сборка pixman"
    (
        cd "$A5_SRC/pixman-$PIXMAN_VERSION"
        ./configure --host=arm-apple-darwin --prefix="$A5_DEPS" \
            --disable-shared --enable-static --disable-dependency-tracking \
            --disable-libpng --disable-gtk
        # Только каталог самой библиотеки: цели demos/ и test/ линкуются в
        # исполняемые файлы для хоста, а собрать их под armv7 нельзя, и
        # отключающего их ключа у pixman нет.
        make -C pixman -j"$(sysctl -n hw.ncpu)"
        make -C pixman install
        cp pixman-1.pc "$A5_DEPS/lib/pkgconfig/"
    )
    mark_built "pixman-$PIXMAN_VERSION"
fi

a5_log "зависимости готовы в $A5_DEPS"
ls "$A5_DEPS/lib" | sed 's/^/    /'
