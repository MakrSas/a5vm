# A5VM — handoff для следующего агента

Дата: 2026-08-11  
Репозиторий: https://github.com/MakrSas/a5vm  
Ветка: agent/initial-a5vm  
HEAD: fa3a4f6 — Use Darwin ARMv7 codegen for QEMU iOS TLS

## Цель

A5VM — экспериментальный UTM-подобный эмулятор для jailbreak iPhone 4S
(iPhone4,1, ARMv7, iOS 6). Требования владельца:

- интерфейс UIKit в стиле iOS 6;
- fullscreen экран VM и стрелка UTM-подобной панели управления;
- одинаковые кнопки с иконками;
- DOS, Windows и позже classic Mac OS;
- OS presets с автоматическим выбором CPU/RAM/devices;
- выбор IMG/ISO/ROM;
- QEMU backend;
- бесплатная сборка GitHub Actions и установка artifact по SSH.

GUI и portable backend работают. Полный QEMU backend ещё не собран и не
подключён к UIKit. Не выдавать проект за законченный эмулятор DOS/Windows.

## Доступ к iPhone

Владелец ранее дал устройство root@192.168.0.109 и SSH option:

    -o HostKeyAlgorithms=+ssh-rsa

Пароль намеренно не хранится в репозитории, документации или CI. Получить его
у владельца перед установкой; не добавлять пароль в commit, workflow или лог.

Проверенная схема установки:

1. Скачать iOS artifact из Actions.
2. Распаковать A5VM.app.
3. Через SFTP загрузить его в /Applications/A5VM.app.
4. Выполнить:

    chmod -R 755 /Applications/A5VM.app
    chown -R mobile:mobile /Applications/A5VM.app
    su mobile -c 'uicache -p /Applications/A5VM.app'
    ls -l /Applications/A5VM.app/A5VM /Applications/A5VM.app/Info.plist

## Проверенное состояние

Actions run 31515523447:

- iOS 6 ARMv7 tool — success;
- portable core Ubuntu — success;
- portable core macOS — success;
- QEMU i386 smoke — success;
- QEMU iOS 6 ARMv7 library — failure;
- общий run — failure только из-за QEMU iOS job.

Зелёный iOS artifact от commit 9ca7fd1 установлен на устройство:

    /Applications/A5VM.app/A5VM       202160 bytes
    /Applications/A5VM.app/Info.plist 1057 bytes

Последний commit fa3a4f6 меняет только QEMU CI script, поэтому установленная
GUI-версия соответствует состоянию 9ca7fd1.

Windows 98 boot image уже загружен на телефон:

    /var/mobile/Documents/Win98-SE-Boot.img
    size 1474560 bytes, owner mobile:mobile, mode 644

Большой Windows 95 ISO не копировался автоматически, чтобы не занимать около
537 MB без подтверждения.

Локальные файлы владельца:

    C:\Users\ngrom\Downloads\Windows_95b_osr21_Russian.iso
    C:\Users\ngrom\Downloads\Windows 98 Second Edition (Boot Disk)\Win98 SE (Boot Disk).img

## Архитектура приложения

### iOS frontend

- app/main.m — entry point;
- app/A5VMAppDelegate.m — window/navigation;
- app/A5VMMachinesViewController.m — VM library, NSUserDefaults, create/delete;
- app/A5VMNewMachineViewController.m — family/version/profile/media wizard;
- app/A5VMMachineSettingsViewController.m — settings, rename, media change, run checks;
- app/A5VMViewController.m — fullscreen runner и controls;
- app/A5VMIconButton.m — vector CoreGraphics icons;
- app/A5VMDisplayView.m — VGA 80x25 text display;
- app/A5VMDiskImageViewController.m — floppy image editor;
- Makefile.ios — Theos iOS 6 ARMv7 build.

Makefile.ios использует:

    TARGET := iphone:clang:6.1:6.0
    ARCHS := armv7

Runner уже имеет fullscreen display, скрытые status/navigation bars, правую
стрелку панели, Run/Reset/Power/Pause/Keyboard icons, равные основные кнопки
40x40, shortcuts Esc/Tab/arrows/Backspace/Enter, keyboard queue и сохранение
floppy плюс отдельного IDE image.

### Portable core

Основные sources:

    include/a5vm/*.h
    src/memory.c src/cpu8086.c src/cpu386.c src/vga_text.c
    src/keyboard.c src/floppy.c src/disk.c src/ide.c
    src/bios.c src/bios386.c src/pic8259.c src/pit8253.c src/machine.c

Есть 8086 interpreter, начальная 386 real/protected mode implementation,
1 MiB memory, VGA text, keyboard queue, floppy, IDE PIO, 16 MiB hard disk,
частичные BIOS INT 10h/13h/16h, PIC/PIT и tests/test_a5vm.c.

Это демонстрационный subset, не полноценный DOS/Windows emulator. Demo boot
sector и простые тестовые boot sectors работают; реальный Windows 95/98
installer пока не проходил smoke test.

## Presets и ограничения

DOS: MS-DOS 6.22, MS-DOS 5.0, FreeDOS. Runnable profile — 8086, 640 KB,
VGA text, floppy IMG/IMA/DSK. Без media создаётся demo disk.

Windows: Windows 3.1, Windows 95, Windows 98. Profile — experimental i386,
VGA, IDE disk plus floppy/ISO media. IMG/IMA/DSK идут в portable 386 floppy
path. ISO блокируется сообщением ISO needs QEMU. Windows boot success не
подтверждён.

MacOS: System 7, Mac OS 8, Mac OS 9 пока только presets. 68k/PowerPC CPU,
ROM и Macintosh video backend отсутствуют; запуск показывает MacOS backend
not ready.

## QEMU

Submodule third_party/qemu:

    repository: https://github.com/utmapp/qemu.git
    branch: ios-support-v5.1.0
    commit: 2fb97f4f833a6442d2b62ca6bdbf80b3e386b133

Документация: docs/QEMU_BACKEND.md. QEMU i386 Linux smoke build и cross-build
libffi, PCRE2, GLib, Pixman работают. QEMU library в iOS artifact не входит.

Точный текущий блокер:

    config-temp/qemu-conf.c:1:8:
    error: thread-local storage is not supported for the current target
    static __thread int tls_var;

Ошибка повторяется с iOS target и с экспериментом fa3a4f6, который компилирует
QEMU sources с ARMv7 Darwin target, но сохраняет iPhoneOS linker. Simple target
split не помог.

Не использовать без доказательства корректности глобальную подмену:

    -D__thread=

Она может сломать per-thread state и многопоточность QEMU. Нужен явный
emulated-TLS adaptation или готовый iOS-compatible patch. Проверить compile,
link, TLS runtime symbols, запуск VM и thread=single/thread=multi.

JIT на jailbroken ARMv7 пока не реализован в A5VM; сейчас portable backend —
обычный interpreter.

## Git

Последние важные commits:

    fa3a4f6 Use Darwin ARMv7 codegen for QEMU iOS TLS
    9ca7fd1 Allow changing VM installation media from settings
    6cd4095 Fix DOS prompt escape in iOS keyboard shortcut
    4f220b3 Render shortcut enter and backspace keys
    9672c6d Clarify IDE storage editor limitation
    cc99c75 Persist separate VM hard disk images
    bce5211 Add iOS 6 VM shortcut keyboard
    5bd3bc2 Guard unsupported VM media in iOS 6 runner
    1d5f811 Use emulated TLS for iOS 6 QEMU
    f983869 Pass iOS flags to QEMU configure
    987b6fb Skip Pixman tests in dependency build

На момент handoff worktree чистое. Не делать destructive reset/checkout без
согласования с владельцем.

## Useful commands

    git status --short
    git log --oneline -12
    git submodule status
    gh run list --repo MakrSas/a5vm --branch agent/initial-a5vm --limit 5
    gh run view <RUN_ID> --repo MakrSas/a5vm --json status,conclusion,jobs
    gh run view <RUN_ID> --repo MakrSas/a5vm --job <JOB_ID> --log-failed

Portable core CI build:

    cc -std=c11 -Wall -Wextra -Werror -I include \
      src/memory.c src/cpu8086.c src/cpu386.c src/vga_text.c src/keyboard.c \
      src/floppy.c src/disk.c src/ide.c src/bios.c src/bios386.c \
      src/pic8259.c src/pit8253.c src/machine.c src/main.c \
      -o build/a5vm-demo

## Приоритеты следующему агенту

1. Исправить QEMU ARMv7 iOS 6 TLS без unsafe глобальной подмены.
2. Получить QEMU dylib artifact и включить его в iOS package.
3. Сделать Objective-C/C bridge: dedicated pthread, lifecycle, VGA framebuffer,
   keyboard/scancode callback и ошибки QMP.
4. Переключить Windows ISO path на QEMU backend.
5. Проверить DOS и Windows 98 boot image на устройстве; затем Windows 95 ISO.
6. Добавить 68k Macintosh backend, ROM validation и MacOS boot.
7. После runtime verification улучшать interpreter/JIT performance.

## Definition of done следующего большого checkpoint

- зелёный iOS 6 GUI artifact;
- QEMU ARMv7 library входит в artifact;
- приложение запускает QEMU, а не только portable demo;
- fullscreen показывает реальный QEMU VGA;
- keyboard доходит до guest;
- Run/Pause/Reset/Power управляют QEMU lifecycle;
- DOS boot и Windows 98 boot IMG проверены на iPhone;
- ISO либо работает, либо честно помечен unsupported;
- MacOS preset работает либо остаётся disabled;
- media и hard disk сохраняются после перезапуска;
- пароли, ROM и ISO не попали в Git.

