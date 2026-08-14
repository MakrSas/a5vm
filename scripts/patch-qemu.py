#!/usr/bin/env python3
"""Правки исходников QEMU, нужные для iOS 6 / ARMv7.

Каждая правка — буквальная замена куска текста, применяется идемпотентно и
проверяется. Отдельным скриптом, а не цепочкой sed/perl в шелле: замены
многострочные и содержат кавычки со слэшами, где экранирование само по себе
становится источником ошибок.

Использование: patch-qemu.py <каталог с исходниками QEMU>
"""
import sys
from pathlib import Path

# Сообщения здесь на русском, а кодировка консоли не везде UTF-8.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def patch(path: Path, old: str, new: str, marker: str, description: str) -> None:
    """Заменяет old на new. Если marker уже в файле, считает правку внесённой."""
    text = path.read_text(encoding="utf-8")

    if marker in text:
        print(f"  = {description} (уже внесена)")
        return

    if old not in text:
        sys.exit(
            f"НЕ НАЙДЕН фрагмент для правки «{description}» в {path}.\n"
            f"Похоже, версия QEMU изменилась — правку нужно пересмотреть, "
            f"а не подгонять вслепую."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    if marker not in path.read_text(encoding="utf-8"):
        sys.exit(f"правка «{description}» применилась, но маркер не появился")
    print(f"  + {description}")


def main() -> None:
    src = Path(sys.argv[1])

    # ------------------------------------------------------------------
    # tcg/arm/tcg-target.h
    #
    # configure включает CONFIG_IOS_JIT для iOS безусловно, а тело
    # flush_dcache_range под этим флагом в апстриме осталось незаконченным:
    # там просто #error. На ARM согласованность кэшей после генерации кода
    # надо обеспечивать явно, иначе процессор исполнит то, что осталось в
    # кэше инструкций от прошлого содержимого этих адресов.
    # sys_dcache_flush — штатный для Дарвина способ, доступный задолго до
    # iOS 6.
    # ------------------------------------------------------------------
    patch(
        src / "tcg/arm/tcg-target.h",
        old=(
            '#if defined(CONFIG_IOS_JIT)\n'
            'static inline void flush_dcache_range(uintptr_t start, uintptr_t stop)\n'
            '{\n'
            '#error "Unimplemented dcache flush function"\n'
            '}\n'
        ),
        new=(
            '#if defined(CONFIG_IOS_JIT)\n'
            '#include <libkern/OSCacheControl.h>\n'
            'static inline void flush_dcache_range(uintptr_t start, uintptr_t stop)\n'
            '{\n'
            '    sys_dcache_flush((void *)start, stop - start);\n'
            '}\n'
        ),
        marker="sys_dcache_flush",
        description="tcg/arm: flush_dcache_range через sys_dcache_flush",
    )

    # ------------------------------------------------------------------
    # util/cacheinfo.c
    #
    # Конструктор init_cache_info падал на настоящем iPhone 4S:
    #   Assertion failed: ((isize & (isize - 1)) == 0)
    #
    # Здесь `long size` не инициализирована, а условие проверяет только код
    # возврата sysctlbyname, но не то, записала ли она хоть что-нибудь в
    # буфер. Если вызов сообщает об успехе, ничего не записав, дальше идёт
    # мусор со стека — и он, разумеется, не степень двойки.
    #
    # Из шелла на том же устройстве `sysctl hw.cachelinesize` честно
    # показывает 32, в том числе от имени mobile, так что дело не в правах:
    # что-то в вызове из конструктора dylib, который dyld выполняет до
    # того, как процесс окончательно поднялся, ведёт себя иначе. Точную
    # причину этого выяснять не обязательно — доверять «успешному» вызову,
    # не заполнившему буфер, нельзя в любом случае.
    #
    # Отброшенное значение уводит в fallback_cache_info с его 64 байтами.
    # Для нашей сборки это безопасно: qemu_icache_linesize и
    # qemu_dcache_linesize используются только для выравнивания и паддинга
    # (ROUND_UP, qemu_memalign, разбиение массива блокировок), а сброс
    # кэша на ARM делает __builtin___clear_cache, который вычисляет
    # геометрию сам.
    # ------------------------------------------------------------------
    patch(
        src / "util/cacheinfo.c",
        old=(
            "    long size;\n"
            "    size_t len = sizeof(size);\n"
            '    if (!sysctlbyname("hw.cachelinesize", &size, &len, NULL, 0)) {\n'
            "        *isize = *dsize = size;\n"
            "    }\n"
        ),
        new=(
            "    long size = 0;\n"
            "    size_t len = sizeof(size);\n"
            '    int rc = sysctlbyname("hw.cachelinesize", &size, &len, NULL, 0);\n'
            "    if (rc == 0 && len == sizeof(size) && size > 0) {\n"
            "        *isize = *dsize = size;\n"
            "    } else {\n"
            "        /* A5VM: не доверяем вызову, сообщившему об успехе, но не\n"
            "           заполнившему буфер — иначе дальше пойдёт мусор со стека. */\n"
            '        fprintf(stderr, "A5VM cacheinfo: rc=%d errno=%d len=%zu size=%ld\\n",\n'
            "                rc, errno, len, size);\n"
            "    }\n"
        ),
        marker="A5VM cacheinfo",
        description="util/cacheinfo.c: проверять, что sysctlbyname заполнила буфер",
    )

    # ------------------------------------------------------------------
    # default-configs/i386-softmmu.mak
    #
    # hw/usb/dev-mtp.c зовёт fdopendir(), которой в заголовках iPhoneOS6.1
    # ещё нет. Проброс каталога хоста в гостя по MTP приложению не нужен ни
    # в каком виде, так что устройство проще выключить, чем добавлять ещё
    # одну заглушку libc.
    # ------------------------------------------------------------------
    config = src / "default-configs/i386-softmmu.mak"
    text = config.read_text(encoding="utf-8")
    if "CONFIG_USB_STORAGE_MTP=n" in text:
        print("  = USB MTP отключён (уже)")
    else:
        config.write_text(text + "\nCONFIG_USB_STORAGE_MTP=n\n", encoding="utf-8")
        print("  + USB MTP отключён")


if __name__ == "__main__":
    main()
