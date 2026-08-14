#!/bin/bash
#
# Общие настройки тулчейна для armv7/iOS 6.  Подключается через `source` из
# остальных скриптов сборки; сам ничего не собирает.
#
# Требует, чтобы A5_SDKROOT указывал на распакованный iPhoneOS6.1.sdk
# (см. scripts/fetch-sdk.sh).
#

set -euo pipefail

A5_SDKROOT=${A5_SDKROOT:?A5_SDKROOT must point at iPhoneOS6.1.sdk}
A5_ARCH=${A5_ARCH:-armv7}
A5_MIN_VERSION=${A5_MIN_VERSION:-6.0}
A5_SDK_VERSION=${A5_SDK_VERSION:-6.1}

A5_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
A5_WORK=${A5_WORK:-"$A5_ROOT/work"}
A5_DEPS="$A5_WORK/deps"
A5_SRC="$A5_WORK/src"

#
# Компилятор берётся из установленного Xcode, а SDK — старый, скачанный
# отдельно.  Комбинация «новый clang + древний sysroot» и есть источник
# почти всех особенностей ниже: сам компилятор про armv7/iOS 6 всё ещё
# знает, а вот заголовки и стабы этого SDK застали далеко не все функции,
# на которые современный компилятор рассчитывает.
#
#
# Python, под которым запускается meson.  Важно, какой именно: meson отдаёт
# сборочным скриптам ровно тот интерпретатор, под которым работает сам, а
# gdbus-codegen в glib 2.76 импортирует distutils, выброшенный из Python
# 3.12.  На macOS-раннере системный python3 уже 3.14, поэтому CI подсовывает
# сюда 3.11 — см. .github/workflows/build.yml.
#
A5_PYTHON=${A5_PYTHON:-python3}

A5_CC=${A5_CC:-$(xcrun --sdk iphoneos --find clang)}
A5_AR=${A5_AR:-$(xcrun --sdk iphoneos --find ar)}
A5_RANLIB=${A5_RANLIB:-$(xcrun --sdk iphoneos --find ranlib)}
A5_STRIP=${A5_STRIP:-$(xcrun --sdk iphoneos --find strip)}

#
# Целевой триплет для всего, что не использует __thread.
#
A5_TARGET="${A5_ARCH}-apple-ios${A5_MIN_VERSION}"
A5_BASE_CFLAGS="-target $A5_TARGET -arch $A5_ARCH -isysroot $A5_SDKROOT \
-miphoneos-version-min=${A5_MIN_VERSION}"

#
# QEMU использует __thread (tcg_ctx, current_cpu, RCU), а clang включает
# поддержку TLS для 32-битного устройства iOS только начиная с деплоймент-
# таргета 9.0: в DarwinTargetInfo стоит буквально
# `TLSSupported = !Triple.isOSVersionLT(9)` для не-симулятора.  Понизить эту
# планку флагом нельзя, а голый armo-triple без "ios" в эту ветку вообще не
# попадает и остаётся с TLSSupported = false.
#
# Поэтому QEMU компилируется и линкуется с триплетом iOS 9.0, но с
# -femulated-tls: код обращается к TLS через вызовы рантайма, а не через
# нативные Mach-O TLV, которых dyld на iOS 6 не понимает.  Настоящий
# минимум 6.0 возвращается в готовую библиотеку через vtool уже после
# линковки — см. build-qemu.sh.
#
A5_TLS_MIN_VERSION=${A5_TLS_MIN_VERSION:-9.0}
A5_QEMU_TARGET="${A5_ARCH}-apple-ios${A5_TLS_MIN_VERSION}"
A5_QEMU_BASE_CFLAGS="-target $A5_QEMU_TARGET -arch $A5_ARCH -isysroot $A5_SDKROOT \
-miphoneos-version-min=${A5_TLS_MIN_VERSION} -femulated-tls"

#
# Начиная с clang 16 набор давних «просто предупреждений» стал ошибками по
# умолчанию: неявное объявление функции, подразумеваемый int, смешение
# несовместимых указателей.  Ни libffi 3.3, ни pixman 0.40, ни QEMU 5.1 под
# такой компилятор не писались — например, libffi зовёт memcpy, не подключив
# <string.h>.  Править чужие релизы по одному месту смысла нет: на armv7 эти
# конструкции работают ровно так, как задумывалось (int и void* здесь оба
# 32-битные и возвращаются в одном регистре), поэтому возвращаем им прежний
# статус предупреждений.
#
A5_LEGACY_C_FLAGS="-Wno-implicit-function-declaration -Wno-implicit-int \
-Wno-int-conversion -Wno-incompatible-pointer-types \
-Wno-incompatible-function-pointer-types -Wno-deprecated-non-prototype"

export A5_ROOT A5_WORK A5_DEPS A5_SRC
export A5_SDKROOT A5_ARCH A5_MIN_VERSION A5_SDK_VERSION
export A5_CC A5_AR A5_RANLIB A5_STRIP A5_PYTHON
export A5_TARGET A5_BASE_CFLAGS
export A5_TLS_MIN_VERSION A5_QEMU_TARGET A5_QEMU_BASE_CFLAGS
export A5_LEGACY_C_FLAGS

a5_log() {
    echo "==> $*"
}
