#!/bin/bash
set -euo pipefail

# Build the smallest useful UTM/QEMU system-emulation library for iPhone 4S.
# The app keeps its portable backend until this library is wired to UIKit.

SDKROOT=${SDKROOT:?SDKROOT must point at iPhoneOS6.1.sdk}
QEMU_SOURCE=${QEMU_SOURCE:?QEMU_SOURCE must point at third_party/qemu}
OUT_DIR=${OUT_DIR:?OUT_DIR must be an output directory}
WORK_DIR=${WORK_DIR:-"$RUNNER_TEMP/a5vm-qemu-ios-work"}
DEPS_DIR="$WORK_DIR/deps"
SRC_DIR="$WORK_DIR/src"
BUILD_DIR="$WORK_DIR/qemu-build"
IOS_MIN_VERSION=${IOS_MIN_VERSION:-6.0}

mkdir -p "$DEPS_DIR" "$SRC_DIR" "$OUT_DIR"

IOS_CFLAGS="-target armv7-apple-ios${IOS_MIN_VERSION} -arch armv7 -isysroot $SDKROOT -miphoneos-version-min=${IOS_MIN_VERSION} -fPIC"
IOS_LDFLAGS="-target armv7-apple-ios${IOS_MIN_VERSION} -arch armv7 -isysroot $SDKROOT -miphoneos-version-min=${IOS_MIN_VERSION}"
export CC="${CC:-$(xcrun --sdk iphoneos --find clang)}"
export CXX="${CXX:-$CC}"
export AR="${AR:-$(xcrun --sdk iphoneos --find ar)}"
export RANLIB="${RANLIB:-$(xcrun --sdk iphoneos --find ranlib)}"
export STRIP="${STRIP:-$(xcrun --sdk iphoneos --find strip)}"
export CPP="${CPP:-$CC -E}"
export CXXCPP="${CXXCPP:-$CC -E -x c}"
export CFLAGS="$IOS_CFLAGS"
export CXXFLAGS="$IOS_CFLAGS"
export LDFLAGS="$IOS_LDFLAGS"
export CPPFLAGS="-I$DEPS_DIR/include"
export PKG_CONFIG_LIBDIR="$DEPS_DIR/lib/pkgconfig:$DEPS_DIR/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export PKG_CONFIG_SYSROOT_DIR=""

dump_config_on_failure() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        while IFS= read -r log; do
            echo "===== $log ====="
            tail -n 80 "$log"
        done < <(find "$WORK_DIR" -name config.log -type f -print)
    fi
    exit "$status"
}
trap dump_config_on_failure EXIT

fetch() {
    local url="$1"
    local archive="$2"
    if [ ! -f "$SRC_DIR/$archive" ]; then
        curl --fail --location --retry 3 "$url" -o "$SRC_DIR/$archive"
    fi
}

unpack() {
    local archive="$1"
    local directory="$2"
    if [ ! -d "$SRC_DIR/$directory" ]; then
        tar -xf "$SRC_DIR/$archive" -C "$SRC_DIR"
    fi
}

build_autotools() {
    local directory="$1"
    shift
    if [ -f "$SRC_DIR/$directory/.a5vm-built" ]; then
        return
    fi
    pushd "$SRC_DIR/$directory" >/dev/null
    ./configure --host=arm-apple-darwin --prefix="$DEPS_DIR" \
        --disable-shared --enable-static "$@"
    make -j2
    make install
    touch .a5vm-built
    popd >/dev/null
}

fetch "https://github.com/libffi/libffi/releases/download/v3.4.4/libffi-3.4.4.tar.gz" libffi-3.4.4.tar.gz
unpack libffi-3.4.4.tar.gz libffi-3.4.4
build_autotools libffi-3.4.4 --disable-dependency-tracking

fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz" pcre2-10.42.tar.gz
unpack pcre2-10.42.tar.gz pcre2-10.42
build_autotools pcre2-10.42 --disable-dependency-tracking \
    --disable-pcre2grep --disable-pcre2test --disable-jit

fetch "https://download.gnome.org/sources/glib/2.76/glib-2.76.6.tar.xz" glib-2.76.6.tar.xz
unpack glib-2.76.6.tar.xz glib-2.76.6
if [ ! -f "$SRC_DIR/glib-2.76.6/.a5vm-built" ]; then
    cat > "$WORK_DIR/ios-armv7-cross.ini" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
ranlib = '$RANLIB'
strip = '$STRIP'
pkgconfig = '$(command -v pkg-config)'

[built-in options]
c_args = ['-target', 'armv7-apple-ios$IOS_MIN_VERSION', '-arch', 'armv7', '-isysroot', '$SDKROOT', '-miphoneos-version-min=$IOS_MIN_VERSION', '-fPIC', '-I$DEPS_DIR/include']
c_link_args = ['-target', 'armv7-apple-ios$IOS_MIN_VERSION', '-arch', 'armv7', '-isysroot', '$SDKROOT', '-miphoneos-version-min=$IOS_MIN_VERSION', '-L$DEPS_DIR/lib']

[host_machine]
system = 'darwin'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
EOF
    pushd "$SRC_DIR/glib-2.76.6" >/dev/null
    meson setup build "$WORK_DIR/ios-armv7-cross.ini" \
        --prefix="$DEPS_DIR" -Dtests=false -Dinstalled_tests=false \
        -Dglib_assert=false -Dglib_checks=false -Dman=false \
        -Dgtk_doc=false -Ddtrace=disabled -Dsystemtap=disabled \
        -Dlibmount=disabled -Dselinux=disabled -Dxattr=false
    meson compile -C build
    meson install -C build
    touch .a5vm-built
    popd >/dev/null
fi

fetch "https://www.cairographics.org/releases/pixman-0.40.0.tar.gz" pixman-0.40.0.tar.gz
unpack pixman-0.40.0.tar.gz pixman-0.40.0
build_autotools pixman-0.40.0 --disable-dependency-tracking --disable-libpng

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR" >/dev/null
"$QEMU_SOURCE/configure" \
    --cc="$CC" --host-cc="$(command -v clang)" --cpu=arm \
    --target-list=i386-softmmu --enable-shared-lib --disable-werror \
    --disable-docs --disable-guest-agent --disable-tools \
    --disable-modules --disable-plugins --disable-cocoa --disable-sdl \
    --disable-gtk --disable-curses --disable-vnc --disable-spice \
    --disable-opengl --audio-drv-list=none --disable-virtfs \
    --disable-slirp --disable-fdt --disable-capstone --disable-curl \
    --disable-gnutls --disable-nettle --disable-gcrypt --disable-libssh \
    --disable-lzo --disable-snappy --disable-zstd --disable-bzip2 \
    --disable-lzfse --disable-seccomp --disable-cap-ng --disable-kvm \
    --disable-hvf --disable-whpx --disable-xen --disable-rdma \
    --disable-vde --disable-netmap --disable-linux-aio --disable-libnfs \
    --disable-libiscsi --disable-pvrdma --disable-usb-redir \
    --disable-libusb --disable-smartcard --disable-tpm --disable-libxml2 \
    --disable-attr --disable-xfsctl --disable-mpath --disable-libpmem \
    --disable-pie --disable-malloc-trim --with-coroutine=libucontext \
    --extra-cflags="-I$DEPS_DIR/include" --extra-ldflags="-L$DEPS_DIR/lib"
make -j2 i386-softmmu/all
popd >/dev/null

QEMU_LIBRARY="$BUILD_DIR/i386-softmmu/libqemu-system-i386.dylib"
test -f "$QEMU_LIBRARY"
cp "$QEMU_LIBRARY" "$OUT_DIR/"
cp -R "$BUILD_DIR/pc-bios" "$OUT_DIR/pc-bios"
cp "$QEMU_SOURCE/COPYING" "$OUT_DIR/QEMU-COPYING"
file "$OUT_DIR/libqemu-system-i386.dylib"
