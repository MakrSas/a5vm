#!/bin/bash
set -euo pipefail

# Build the smallest useful UTM/QEMU system-emulation library for iPhone 4S.
# The app keeps its portable backend until this library is wired to UIKit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDKROOT=${SDKROOT:?SDKROOT must point at iPhoneOS6.1.sdk}
QEMU_SOURCE=${QEMU_SOURCE:?QEMU_SOURCE must point at third_party/qemu}
OUT_DIR=${OUT_DIR:?OUT_DIR must be an output directory}
WORK_DIR=${WORK_DIR:-"$RUNNER_TEMP/a5vm-qemu-ios-work"}
DEPS_DIR="$WORK_DIR/deps"
SRC_DIR="$WORK_DIR/src"
BUILD_DIR="$WORK_DIR/qemu-build"
IOS_MIN_VERSION=${IOS_MIN_VERSION:-6.0}
IOS_SDK_VERSION=${IOS_SDK_VERSION:-6.1}
# Apple clang's DarwinTargetInfo (clang/lib/Basic/Targets/OSTargets.h) only
# flips TLSSupported on for a 32-bit, non-simulator iOS triple when
# `!Triple.isOSVersionLT(9)` -- i.e. the *compile-time* deployment target
# must claim iOS 9.0 or later for __thread to be allowed on armv7 at all;
# there is no lower Apple-supported floor to target instead. A bare,
# OS-less "armv7-apple-darwin" triple does not take that iOS branch either
# (isiOS() is false for it), so TLSSupported keeps the constructor's
# initial `false` -- it fails exactly the same way, just for a different
# reason. -femulated-tls only picks the codegen *strategy* (portable
# runtime calls instead of native Mach-O TLV, so no iOS 8/9 dyld TLV
# support is required at runtime); it never overrides this frontend gate.
# QEMU is only ever run on this device via A5VM's own pthread bridge, so
# the artificially high compile-time deployment target has no effect on
# API availability in practice (QEMU touches no post-6.x iOS API), and the
# actual shipped iOS 6.0 minimum is restored on the finished dylib by the
# `vtool` call below.
QEMU_TLS_MIN_VERSION="9.0"

mkdir -p "$DEPS_DIR" "$SRC_DIR" "$OUT_DIR"

# iOS 6 on ARMv7 has no native ELF TLS.  Clang's emulated TLS keeps QEMU's
# per-thread CPU/runtime state available on this deployment target.
IOS_CFLAGS="-target armv7-apple-ios${IOS_MIN_VERSION} -arch armv7 -isysroot $SDKROOT -miphoneos-version-min=${IOS_MIN_VERSION} -fPIC -femulated-tls"
IOS_LDFLAGS="-target armv7-apple-ios${IOS_MIN_VERSION} -arch armv7 -isysroot $SDKROOT -miphoneos-version-min=${IOS_MIN_VERSION}"
# Compile and link QEMU itself against the iOS 9.0 triple that satisfies
# the TLSSupported gate above (see QEMU_TLS_MIN_VERSION).  CFLAGS and
# LDFLAGS must agree exactly: configure's probes (e.g. its unconditional
# __thread check) build each probe with one clang invocation using both
# together, and the *last* -target flag on that command line wins for the
# whole invocation, so any mismatch between them silently changes which
# target the probe actually compiles against.
QEMU_CFLAGS="-target armv7-apple-ios${QEMU_TLS_MIN_VERSION} -arch armv7 -isysroot $SDKROOT -miphoneos-version-min=${QEMU_TLS_MIN_VERSION} -fPIC -femulated-tls"
# The final `make` link step (rules.mak's LINK rule) uses $(CFLAGS)
# $(QEMU_LDFLAGS), not QEMU_CXXFLAGS -- so -stdlib=libc++ from
# --extra-cxxflags never reaches it, and the link fails with undefined
# libc++abi (vtables/RTTI, operator new/delete, the ARM32 SJLJ exception
# personality routine) plus libSystem math/compiler-rt symbols
# (___clear_cache, ___exp10, ___sincos_stret) that this unusual
# old-sysroot/new-toolchain combination does not appear to auto-link by
# default. -lc++ and an explicit -lSystem here are harmless, standard
# additions for every QEMU_LDFLAGS use (including configure's C-only
# probes, which just gain an unused-but-harmless link library, unlike a
# compile-strategy flag such as -stdlib= that could trip their -Werror).
QEMU_LDFLAGS="-target armv7-apple-ios${QEMU_TLS_MIN_VERSION} -arch armv7 -isysroot $SDKROOT -miphoneos-version-min=${QEMU_TLS_MIN_VERSION} -lc++ -lSystem"
# The iPhoneOS6.1 SDK predates clock_gettime()/CLOCK_MONOTONIC on Apple
# platforms; force-include a small compat shim ahead of every QEMU
# translation unit instead of patching the vendored QEMU source (see
# qemu-ios-clock-compat.h for why).
QEMU_CFLAGS="$QEMU_CFLAGS -include $SCRIPT_DIR/qemu-ios-clock-compat.h"
# accel/tcg/translate-all.c's CONFIG_IOS_JIT alloc_jit_rw_mirror() (real,
# used mach_vm_remap() code for the classic iOS dual RX/RW JIT-buffer
# mapping trick, not a stub) uses VM_FLAGS_RANDOM_ADDR, an XNU vm_map(2)
# flag bit the iPhoneOS6.1 SDK's <mach/vm_statistics.h> predates. The
# value is a stable kernel-ABI constant (the kernel itself interprets
# this bit, so it cannot change meaning across OS versions without
# breaking old binaries), so define it directly rather than shim a
# header for one macro.
QEMU_CFLAGS="$QEMU_CFLAGS -DVM_FLAGS_RANDOM_ADDR=0x00000800"
export CC="${CC:-$(xcrun --sdk iphoneos --find clang)}"
export CXX="${CXX:-$CC}"
# clang's automatic libc++ header search apparently does not kick in for
# this ancient, non-Xcode-bundled iPhoneOS6.1 sysroot -- QEMU's
# disas/libvixl (a real C++ component, pulled in by any ARM host --cpu
# regardless of --target-list) fails to find <cmath> otherwise, even with
# -stdlib=libc++ passed via --extra-cxxflags. Modern Xcode bundles a
# separate usr/include/c++/v1 *per platform SDK* rather than once under
# the shared toolchain, so search broadly for the real cmath and use
# whichever location actually has it -- but search the Xcode-bundled
# iPhoneOS SDK first specifically, before any other platform's SDK
# (AppleTVOS, WatchOS, MacOSX, ...) also sitting under the same Developer
# directory: the first build of this fix picked AppleTVOS.sdk's copy
# purely because it happened to sort first, which is wrong for an ARM
# iOS binary even though iPhoneOS26.0.sdk was sitting right there too.
XCODE_DEVELOPER_DIR="$(xcode-select -p)"
MODERN_IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
QEMU_CXX_STD_INCLUDE="$(find "$MODERN_IPHONEOS_SDK" "$XCODE_DEVELOPER_DIR" "$SDKROOT" -path '*/c++/v1/cmath' -print -quit 2>/dev/null)"
QEMU_CXX_STD_INCLUDE="${QEMU_CXX_STD_INCLUDE%/cmath}"
if [ -z "$QEMU_CXX_STD_INCLUDE" ]; then
    echo "::warning::No libc++ v1/cmath found under $MODERN_IPHONEOS_SDK, $XCODE_DEVELOPER_DIR or $SDKROOT" >&2
fi
QEMU_CXXFLAGS_EXTRA="-stdlib=libc++${QEMU_CXX_STD_INCLUDE:+ -isystem $QEMU_CXX_STD_INCLUDE}"
export AR="${AR:-$(xcrun --sdk iphoneos --find ar)}"
export RANLIB="${RANLIB:-$(xcrun --sdk iphoneos --find ranlib)}"
export STRIP="${STRIP:-$(xcrun --sdk iphoneos --find strip)}"
export CPP="${CPP:-$CC $IOS_CFLAGS -E}"
export CXXCPP="${CXXCPP:-$CC $IOS_CFLAGS -E -x c++ -nostdinc++}"
export CFLAGS="$IOS_CFLAGS"
export CXXFLAGS="$IOS_CFLAGS -nostdinc++"
export LDFLAGS="$IOS_LDFLAGS"
export CPPFLAGS="-I$DEPS_DIR/include -DPAGE_MAX_SIZE=4096 -DPAGE_MAX_SHIFT=12"
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
        if [ -f "$BUILD_DIR/config-host.mak" ]; then
            echo "===== $BUILD_DIR/config-host.mak (CFLAGS/CXXFLAGS) ====="
            grep -E '^(CFLAGS|CXXFLAGS|QEMU_CFLAGS|QEMU_CXXFLAGS)=' "$BUILD_DIR/config-host.mak"
        fi
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

build_autotools_install_only() {
    local directory="$1"
    shift
    if [ -f "$SRC_DIR/$directory/.a5vm-built" ]; then
        return
    fi
    pushd "$SRC_DIR/$directory" >/dev/null
      ./configure --host=arm-apple-darwin --prefix="$DEPS_DIR" \
          --disable-shared --enable-static "$@"
      # Pixman 0.40.0 has no configure switch for its test suite.  Its
      # top-level install target recurses into test/, whose host-only helper
      # symbols cannot be linked for armv7.  Install the library and headers
      # while leaving the optional demos/tests out of the recursion.
      perl -0pi -e 's/^SUBDIRS = pixman demos test$/SUBDIRS = pixman/m' Makefile
      make -j2 install
    touch .a5vm-built
    popd >/dev/null
}

fetch "https://github.com/libffi/libffi/releases/download/v3.4.7/libffi-3.4.7.tar.gz" libffi-3.4.7.tar.gz
unpack libffi-3.4.7.tar.gz libffi-3.4.7
LIBFFI_ARM_SOURCE="$SRC_DIR/libffi-3.4.7/src/arm/sysv.S"
perl -0pi -e 's/(ARM_FUNC_START\(ffi_call_VFP\)\n\s*UNWIND\(\.fnstart\)\n)\s*cfi_startproc/$1/' "$LIBFFI_ARM_SOURCE"
perl -0pi -e 's/(ARM_FUNC_START\(ffi_call_SYSV\)\n)/$1\tcfi_startproc\n/' "$LIBFFI_ARM_SOURCE"
build_autotools libffi-3.4.7 --disable-dependency-tracking

fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz" pcre2-10.42.tar.gz
unpack pcre2-10.42.tar.gz pcre2-10.42
build_autotools pcre2-10.42 --disable-dependency-tracking \
    --disable-pcre2grep --disable-pcre2test --disable-jit

fetch "https://download.gnome.org/sources/glib/2.76/glib-2.76.6.tar.xz" glib-2.76.6.tar.xz
unpack glib-2.76.6.tar.xz glib-2.76.6
GLIB_GSPAWN_SOURCE="$SRC_DIR/glib-2.76.6/glib/gspawn.c"
perl -0pi -e 's/#ifdef __APPLE__\n#include <libproc\.h>\n#include <sys\/proc_info\.h>\n#endif/#if defined(__APPLE__) \&\& !defined(A5VM_IOS_BUILD)\n#include <libproc.h>\n#include <sys\/proc_info.h>\n#endif/' "$GLIB_GSPAWN_SOURCE"
perl -0pi -e 's/#if defined\(__APPLE__\)\n  \/\* proc_pidinfo/#if defined(__APPLE__) \&\& !defined(A5VM_IOS_BUILD)\n  \/\* proc_pidinfo/' "$GLIB_GSPAWN_SOURCE"
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
c_args = ['-target', 'armv7-apple-ios$IOS_MIN_VERSION', '-arch', 'armv7', '-isysroot', '$SDKROOT', '-miphoneos-version-min=$IOS_MIN_VERSION', '-fPIC', '-I$DEPS_DIR/include', '-DA5VM_IOS_BUILD']
c_link_args = ['-target', 'armv7-apple-ios$IOS_MIN_VERSION', '-arch', 'armv7', '-isysroot', '$SDKROOT', '-miphoneos-version-min=$IOS_MIN_VERSION', '-L$DEPS_DIR/lib']

[host_machine]
system = 'darwin'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
EOF
    pushd "$SRC_DIR/glib-2.76.6" >/dev/null
    python3 -m mesonbuild.mesonmain setup build --cross-file "$WORK_DIR/ios-armv7-cross.ini" \
        --prefix="$DEPS_DIR" -Dtests=false -Dinstalled_tests=false \
        -Dglib_assert=false -Dglib_checks=false -Dman=false \
        -Dgtk_doc=false -Ddtrace=false -Dsystemtap=false \
        -Dlibmount=disabled -Dselinux=disabled -Dxattr=false
    python3 -m mesonbuild.mesonmain compile -C build
    python3 -m mesonbuild.mesonmain install -C build
    touch .a5vm-built
    popd >/dev/null
fi

fetch "https://www.cairographics.org/releases/pixman-0.40.0.tar.gz" pixman-0.40.0.tar.gz
unpack pixman-0.40.0.tar.gz pixman-0.40.0
CFLAGS="$IOS_CFLAGS -Wno-incompatible-function-pointer-types"
build_autotools_install_only pixman-0.40.0 --disable-dependency-tracking --disable-libpng
CFLAGS="$IOS_CFLAGS"

# hw/usb/dev-mtp.c (an MTP host-directory-passthrough USB device, on by
# default for i386-softmmu via hw/usb/Kconfig's "config USB_STORAGE_MTP
# / default y / depends on USB") calls fdopendir(), which the
# iPhoneOS6.1 SDK's headers do not declare -- one more POSIX addition
# from after this SDK's era, like clock_gettime. A5VM only needs floppy
# and IDE disk emulation for DOS/Windows, never host MTP passthrough, so
# drop the whole feature instead of shimming another libc function:
# default-configs/i386-softmmu.mak documents exactly this override
# mechanism ("uncomment to disable these optional devices"), just
# without USB_STORAGE_MTP pre-listed there.
echo "CONFIG_USB_STORAGE_MTP=n" >> "$QEMU_SOURCE/default-configs/i386-softmmu.mak"

# tcg/arm/tcg-target.h's flush_dcache_range() -- needed to make freshly
# JIT-generated ARM code actually visible to the icache -- is a stub for
# CONFIG_IOS_JIT (which configure always turns on for $ios = yes, no
# opt-out flag exists): its body is a bare #error, apparently left
# unfinished upstream. Fill in the standard Darwin primitive for this
# (sys_dcache_flush, from libkern/OSCacheControl.h, available on iOS
# since long before iOS 6) rather than disabling CONFIG_IOS_JIT wholesale
# and losing whatever else it gates in the surrounding TCG/JIT plumbing.
TCG_ARM_TARGET_H="$QEMU_SOURCE/tcg/arm/tcg-target.h"
perl -0pi -e 's/(#if defined\(CONFIG_IOS_JIT\)\n)(static inline void flush_dcache_range\(uintptr_t start, uintptr_t stop\)\n\{\n)#error "Unimplemented dcache flush function"/$1#include <libkern\/OSCacheControl.h>\n$2    sys_dcache_flush((void *)start, stop - start);/' "$TCG_ARM_TARGET_H"
grep -q "sys_dcache_flush" "$TCG_ARM_TARGET_H" || { echo "Failed to patch $TCG_ARM_TARGET_H" >&2; exit 1; }

# configure defaults an iOS host to the "libucontext" coroutine backend
# (native Darwin ucontext is skipped entirely for the whole Darwin family
# by configure's own probe, and --with-coroutine=ucontext hard-errors
# there). The libucontext submodule this fork vendors, though, is a
# Linux/glibc-kernel-ABI reimplementation (github.com/utmapp/libucontext,
# part of the gcompat project) with no Darwin code path anywhere in its
# tree: its arch/arm/makecontext.c hard-codes Linux sigcontext field names
# (uc_mcontext.arm_lr, .arm_r0, ...) that do not exist in Darwin's
# mcontext_t, and relies on a GNU alias() attribute Mach-O cannot link.
# QEMU's own sigaltstack coroutine backend is portable POSIX C with no
# per-architecture assembly and is explicitly accepted by configure for
# Darwin, so use that instead of trying to port libucontext's ARM asm.
#
# configure enables the (C++) AArch64 "libvixl" disassembler whenever the
# host --cpu is any flavor of arm and a C++ compiler is present, regardless
# of --target-list, since it can disassemble host TCG code on any ARM host.
# It needs real C++ standard headers, so do not add -nostdinc++ to its
# flags (fine for the plain-C autotools deps above, since none of them
# compile any C++). That alone was not enough, though: clang's automatic
# libc++ header search does not kick in for this non-Xcode-bundled
# iPhoneOS6.1 sysroot, so -stdlib=libc++ plus an explicit -isystem into
# the toolchain's own libc++ (QEMU_CXXFLAGS_EXTRA, set above once CC is
# known) is required. It is passed only via --extra-cxxflags, which
# configure keeps separate from --extra-cflags/QEMU_CFLAGS -- the C-only
# probes (like the __thread check) must not see -stdlib=libc++, an
# argument clang rejects for C with configure's probe-local -Werror.
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR" >/dev/null
CFLAGS="$QEMU_CFLAGS -I$DEPS_DIR/include" \
CXXFLAGS="$QEMU_CFLAGS $QEMU_CXXFLAGS_EXTRA -I$DEPS_DIR/include" \
CPPFLAGS="-I$DEPS_DIR/include -DPAGE_MAX_SIZE=4096 -DPAGE_MAX_SHIFT=12" \
LDFLAGS="$QEMU_LDFLAGS -L$DEPS_DIR/lib" \
"$QEMU_SOURCE/configure" \
    --cc="$CC" --host-cc="$(command -v clang)" --cpu=arm \
    --audio-drv-list= \
    --target-list=i386-softmmu --enable-shared-lib --disable-werror \
    --disable-docs --disable-guest-agent --disable-tools \
    --disable-modules --disable-plugins --disable-cocoa --disable-sdl \
    --disable-gtk --disable-curses --disable-vnc --disable-spice \
    --disable-opengl --disable-virtfs \
    --disable-slirp --disable-fdt --disable-capstone --disable-curl \
    --disable-gnutls --disable-nettle --disable-gcrypt --disable-libssh \
    --disable-lzo --disable-snappy --disable-zstd --disable-bzip2 \
    --disable-lzfse --disable-seccomp --disable-cap-ng --disable-kvm \
    --disable-hvf --disable-whpx --disable-xen --disable-rdma \
    --disable-vde --disable-netmap --disable-linux-aio --disable-libnfs \
    --disable-libiscsi --disable-pvrdma --disable-usb-redir \
    --disable-libusb --disable-smartcard --disable-tpm --disable-libxml2 \
    --disable-attr --disable-xfsctl --disable-mpath --disable-libpmem \
      --disable-pie --disable-malloc-trim --with-coroutine=sigaltstack \
      --extra-cflags="$QEMU_CFLAGS -I$DEPS_DIR/include" \
      --extra-cxxflags="$QEMU_CXXFLAGS_EXTRA" \
      --extra-ldflags="$QEMU_LDFLAGS -L$DEPS_DIR/lib"
make -j2 V=1 i386-softmmu/all
popd >/dev/null

QEMU_LIBRARY="$BUILD_DIR/i386-softmmu/libqemu-system-i386.dylib"
test -f "$QEMU_LIBRARY"
# QEMU_LDFLAGS claims an iOS 9.0 deployment target only to satisfy clang's
# TLS gate (see QEMU_TLS_MIN_VERSION above), so the linker wrote an iOS 9.0
# platform/version load command.  Overwrite it with the real iOS 6.0
# deployment target so the device's dyld does not refuse to load a dylib
# that (falsely) claims to require iOS 9.
xcrun --sdk iphoneos vtool -set-build-version ios "$IOS_MIN_VERSION" "$IOS_SDK_VERSION" \
    -replace -output "$QEMU_LIBRARY" "$QEMU_LIBRARY"
cp "$QEMU_LIBRARY" "$OUT_DIR/"
cp -R "$BUILD_DIR/pc-bios" "$OUT_DIR/pc-bios"
cp "$QEMU_SOURCE/COPYING" "$OUT_DIR/QEMU-COPYING"
file "$OUT_DIR/libqemu-system-i386.dylib"
