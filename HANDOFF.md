# A5VM — handoff для следующего агента

Дата: 2026-08-12  
Репозиторий: https://github.com/MakrSas/a5vm  
Ветка: agent/initial-a5vm  
HEAD: ea71a3d — Wire A5VMQemuBridge into A5VMViewController

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

Actions run 31591059675 (commit 15eb0ff) — **весь pipeline зелёный**,
включая линковку `A5VMQemuBridge.m` против настоящей QEMU dylib:
`Linking application A5VM (armv7)…` прошёл без единой ошибки undefined
symbol. Значит ВСЕ вручную объявленные ABI-сигнатуры в
`app/A5VMQemuBridge.m` (qemu_init, qemu_main_loop, qemu_cleanup, vm_start,
vm_stop, qemu_system_reset_request, qemu_system_powerdown_request,
qemu_console_lookup_by_index, qemu_input_event_send_key_qcode,
register_displaychangelistener, unregister_displaychangelistener,
qemu_console_surface, четыре pixman_image_get_* функции) совпали с
реальными экспортированными символами в собранной библиотеке — весомое
подтверждение на уровне символов, но НЕ доказательство рантайм-корректности
(структуры типа DisplayChangeListenerOps совпадают по layout только если
компилятор одинаково укладывает поля, что должно быть так при одинаковом
таргете/компиляторе, но не проверено на реальном запуске).

`a5vm-ios6-gui-15eb0ff...` artifact (~28 MB) содержит `A5VM.app/A5VM`
(линкован против QEMU) + `libqemu-system-i386.dylib` + `pc-bios/` +
`QEMU-COPYING`. Bridge НЕ вызывается ниоткуда в UI — `A5VMQemuBridge`
самодостаточный, скомпилированный, но не подключённый класс (см. раздел
"ObjC/C bridge" ниже и приоритет 3).

Установленная на устройстве GUI-сборка ещё СТАРАЯ (commit 9ca7fd1, без QEMU
внутри):

    /Applications/A5VM.app/A5VM       202160 bytes
    /Applications/A5VM.app/Info.plist 1057 bytes

Новый artifact с QEMU внутри на устройство ещё не заливался — владелец
сказал "пиши, потом проверим на устройстве" (2026-08-12), но реальный
device-тест ещё предстоит сделать.

Actions run 31594064160 (commit ea71a3d) — **весь pipeline снова зелёный**
после того, как `A5VMQemuBridge` полностью подключён к `A5VMViewController`
(Run/Pause/Reset/Power/keyboard/textField, delegate callbacks,
`A5VMDisplayView` в растровом режиме). Линковка `ios-armv7` job прошла без
единой ошибки. Тем не менее `_usesQemu` остаётся структурно недостижимым —
`A5VMMachineSettingsViewController.m`'s `runMachine:` по-прежнему блокирует
любой ISO-путь алертом "ISO needs QEMU" до того, как `A5VMViewController`
вообще создаётся (см. ниже, пункт 2 в разделе "ObjC/C bridge" — это
осознанно не тронуто). Значит вся wiring-логика скомпилирована и линкуется,
но ни разу не выполнялась даже локально — сначала нужен явный владельческий
switch-on или изолированный device-тест `qemu_init()`, потом можно
устанавливать новый артефакт и ожидать реального QEMU-запуска.

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

Документация: docs/QEMU_BACKEND.md. Вся сборка (i386 Linux smoke, deps
cross-build, iOS ARMv7 library) теперь зелёная.

### Как был исправлен QEMU ARMv7 iOS build (12 отдельных причин)

Все фиксы — в `ci/build-qemu-ios-armv7.sh` + два новых файла
`ci/qemu-ios-clock-compat.h` и `ci/qemu-ios-libc-compat.c`. По порядку,
каждый следующий баг открывался только после фикса предыдущего:

1. **TLS gate.** Apple clang (`DarwinTargetInfo`, `OSTargets.h`) включает
   `TLSSupported` для 32-бит iOS не-симулятора только при
   `!Triple.isOSVersionLT(9)` — то есть нужен deployment target **iOS 9.0+**,
   не 8.0. Голый `armv7-apple-darwin` (без "ios") тоже не работает — попадает
   в default `false` того же конструктора. Компилируем и линкуем QEMU под
   `-target armv7-apple-ios9.0` (переменная `QEMU_TLS_MIN_VERSION`), а
   `-femulated-tls` всё равно даёт portable codegen без зависимости от
   реального iOS 9 dyld. `vtool -set-build-version ios 6.0 6.1 -replace`
   после линковки возвращает библиотеке настоящий iOS 6.0 minos.
   Критично: `QEMU_CFLAGS` и `QEMU_LDFLAGS` должны быть идентичны — configure
   склеивает их в один вызов clang для проверок, и выигрывает последний
   `-target` в команде.
2. **`--audio-drv-list=none` невалиден.** iOS-ветка в этом форке уже сама
   ставит `audio_drv_list=""` по умолчанию; "none" не входит в whitelist.
   Убрано, оставлено `--audio-drv-list=`.
3. **`libucontext` не портирован на Darwin.** Вендоренный сабмодуль
   (github.com/utmapp/libucontext, проект gcompat) — чистая Linux/glibc
   ABI реализация, нигде в дереве нет Darwin-кода. `--with-coroutine=sigaltstack`
   вместо `libucontext` — портируемый POSIX-бэкенд, который configure и так
   принимает для Darwin.
4. **`clock_gettime`/`CLOCK_MONOTONIC` не объявлены** в iPhoneOS6.1 SDK (Apple
   добавила их около iOS 10). `qemu-ios-clock-compat.h` — компат-шim на
   `mach_absolute_time()`/`gettimeofday()`, подключается через
   `-include` для каждого translation unit.
5. **`<cmath>` не находится** для `disas/libvixl` (C++ AArch64-дизассемблер,
   которого QEMU всегда тянет для любого ARM-хоста, вне зависимости от
   `--target-list`). Современный Xcode хранит `c++/v1` заголовки отдельно
   **на каждый platform SDK**, а не в одном тулчейне. Ищем реальный `cmath`
   через `find`, сначала в bundled iPhoneOS SDK, передаём через
   `--extra-cxxflags` (не через `QEMU_CFLAGS`/`QEMU_LDFLAGS` — иначе
   `-stdlib=libc++` попадёт в C-only probes с их локальным `-Werror`).
6. **`fdopendir` не объявлен** — `hw/usb/dev-mtp.c` (MTP passthrough,
   A5VM не нужен). Отключено через `CONFIG_USB_STORAGE_MTP=n`, дописанное в
   `default-configs/i386-softmmu.mak`.
7. **`tcg/arm/tcg-target.h`: `#error "Unimplemented dcache flush function"`**
   под `CONFIG_IOS_JIT` (который configure всегда включает для iOS, без
   опции отключить) — незаконченный upstream-стаб. Патчится на лету через
   `perl` — вставляется реализация через `sys_dcache_flush()`
   (`libkern/OSCacheControl.h`).
8. **`VM_FLAGS_RANDOM_ADDR` не объявлена** — стабильная XNU vm_map(2)
   константа (`0x00000800`), просто отсутствует в старом SDK; передана через
   `-D`.
9. **Не хватало `-lc++`/`-lSystem` на линковке.** Финальный `LINK` в
   `rules.mak` использует `$(CFLAGS) $(QEMU_LDFLAGS)`, а не
   `QEMU_CXXFLAGS` — `-stdlib=libc++` из `--extra-cxxflags` туда не попадает.
10. **`___clear_cache`/`___exp10`/`___sincos_stret` не резолвятся.**
    `___clear_cache` — реальный вызов `__builtin___clear_cache` из
    `flush_icache_range()`; ни libSystem, ни compiler-rt его не дают на этой
    комбинации SDK/target — реализован в `qemu-ios-libc-compat.c` через
    `sys_icache_invalidate()` (сигнатура обязана быть `void*,void*` — это
    ожидаемый тип clang-билтина). `___exp10`/`___sincos_stret` — Apple
    переименовывает `pow(10,x)` и парные `sin(x)`/`cos(x)` (буквально в
    `target/i386/fpu_helper.c`'s FSINCOS) в свои ABI-варианты для этого
    таргета; отключено через `-fno-builtin-sin -fno-builtin-cos
    -fno-builtin-sincos -fno-builtin-exp10 -fno-builtin-pow`. Важно:
    `-fno-builtin-sincos` одной не хватает — в коде нет буквального вызова
    `sincos()`, слияние идёт по отдельным `sin`/`cos`.

Всё найдено через полный лог CI (`gh run view --log`, полезно грепать
`config-host.mak`/`V=1` вывод — в `dump_config_on_failure()` в скрипте уже
добавлен дамп `CFLAGS`/`QEMU_CXXFLAGS`), НЕ угадыванием — каждая гипотеза
проверялась либо чтением исходников clang/QEMU, либо явным анализом лога
перед следующим пушем.

JIT на jailbroken ARMv7 пока не реализован в A5VM; сейчас portable backend —
обычный interpreter. Сама QEMU-библиотека, впрочем, теперь собирается с
рабочим `CONFIG_IOS_JIT` (dcache flush) — это для её СОБСТВЕННОГО TCG JIT,
когда/если она будет реально запущена на устройстве.

## ObjC/C bridge (app/A5VMQemuBridge.h/.m)

Реализует приоритет 3 полностью на уровне кода: класс написан, линкуется и
теперь подключён к `A5VMViewController` (commit ea71a3d) — но остаётся
структурно недостижимым в реальном использовании, см. пункт 2 ниже.

Lifetime bridge-объекта исправлен: `-startWithArguments:` делает
`[self retain]` перед `pthread_create`, парный `[self release]` — в
`-notifyStopped` (успешный путь) и сразу после неудачного
`pthread_create` (провальный путь). Без этого caller, роняющий свою
последнюю ссылку на bridge (пользователь выходит с экрана VM) во время
работы `qemu_main_loop()`, освободил бы память, в которую всё ещё пишет
живой detached-поток.

Дизайн: bridge и QEMU работают в ОДНОМ процессе (та же shared library), так
что управление идёт напрямую через C API QEMU (`vm_start`/`vm_stop`,
`qemu_system_reset_request`, `qemu_system_powerdown_request`,
`qemu_input_event_send_key_qcode`), а не через QMP — не нужен монитор-сокет
и JSON. QEMU headers НЕ инклюдятся (они требуют весь internal CONFIG_*
header tree, собранный со специфичными флагами `ci/build-qemu-ios-armv7.sh`,
не совместимыми с отдельной Theos-сборкой Makefile.ios) — вместо этого
`A5VMQemuBridge.m` вручную объявляет нужные extern-прототипы и layout
структур (`DisplaySurface`, `DisplayChangeListener`,
`DisplayChangeListenerOps`), скопированные из `third_party/qemu`'s headers
и `qapi/*.json` на текущем pinned commit. **Если submodule когда-нибудь
обновится — эти объявления надо сверить заново.**

Экран: `dpy_gfx_update`/`dpy_gfx_switch` коллбэки регистрируются через
`register_displaychangelistener()` после `qemu_init()` (до
`qemu_main_loop()`), копируют pixman-surface в `UIImage` и отдают в
делегата на main thread. Предполагается формат `PIXMAN_x8r8g8b8`
(дефолтный VGA surface QEMU) — **не проверено на реальном экране**; если
цвета окажутся перепутаны, смотри комментарий в `A5VMQemuDeliverImage`.

Известный, непреодолимый в лоб риск: `qemu_init()` при плохом argv зовёт
`exit()` напрямую (это код обычного standalone-приложения, просто
собранный как shared lib) — упадёт весь процесс A5VM, не только поток
bridge. Значит argv, который будет строить будущий integration-код,
должен быть тем, что `qemu_init()` штатно принимает как обычную
командную строку QEMU.

Что осталось для реальной интеграции в приоритете 3:

1. ~~Собрать argv из конфигурации машины.~~ **Готово** —
   `+[A5VMQemuBridge argumentsWithRAMMegabytes:driveImagePath:isISO:]`
   (commit 9dde5d2). RAM зажат в [16, 512] MB (не доверяем строке из
   конфига напрямую — `qemu_init()` делает `exit()` всего процесса на
   неприемлемо маленьком `-m`). `-display none -monitor none -serial none
   -parallel none` — единственный рабочий выбор в этой сборке (SDL/GTK/
   curses/VNC/spice/cocoa не скомпилированы), не запасной вариант.
2. **Осознанно НЕ сделано**: какие profiles идут через
   `A5VMQemuBridge`, решает `A5VMMachineSettingsViewController.m`'s
   `runMachine:` — сейчас там жёсткий блок "ISO needs QEMU" (алерт,
   `return`, до `A5VMViewController` дело не доходит). Не убирал его
   специально: замена safe-сообщения на попытку реального (ещё ни разу
   не запущенного на устройстве) QEMU-boot — это продуктовое решение с
   риском крэша при первом же launch, а не просто "доделать код". Нужно
   явное решение владельца, когда переключать, или сначала подтвердить
   на устройстве базовый сценарий (`qemu_init()` с простым argv не
   падает) отдельно от основного пользовательского флоу.
3. ~~Растровый режим A5VMDisplayView.~~ **Готово** — `-setFramebufferImage:`
   (commit 2215158), сосуществует с `-setTextBuffer:` (последний
   вызванный режим побеждает).
4. ~~Подключить Run/Pause/Reset/Power к `-pause`/`-resume`/`-requestReset`/
   `-requestPowerDown`.~~ **Готово** (commit ea71a3d) —
   `A5VMViewController`'s `-runDemo:`/`-resetVM:`/`-powerVM:`/`-pauseVM:`/
   `-sendSpecialKey:`/`-textFieldShouldReturn:` все ветвятся на `_usesQemu`
   в начале метода и вызывают bridge вместо interpreter-логики.
   `-stopRunner` (общий teardown, вызывается из `-dealloc` и
   `-viewWillDisappear:`) шлёт `-requestPowerDown`, если bridge ещё
   работает; `-dealloc` перед `[_qemuBridge release]` обнуляет
   `_qemuBridge.delegate`, чтобы отложенный `dispatch_async`-колбэк не
   попал в уже освобождаемый view controller. Добавлен отдельный
   `-qemuMediaPath` (resolve absolute/Documents-relative, как в
   `A5VMMachineSettingsViewController`'s `runMachine:`) — **важно**:
   существовавший `-bootImagePath` для ISO-медиа тихо возвращал бы путь
   floppy-`.dsk`-образа (он написан только для portable-интерпретатора),
   так что `-runDemo:` в QEMU-ветке использует именно `-qemuMediaPath`,
   а не `-bootImagePath`.
5. Реальный device-тест: устанавливается ли `A5VM.app` с dylib внутри без
   краша при запуске (проверяет `install_name_tool -id
   @executable_path/...` из `ci/build-qemu-ios-armv7.sh` и линковку
   Makefile.ios), и не падает ли `qemu_init()` с валидным argv из пункта 1.
   Владелец предложил root-доступ по SSH для этого теста. **Единственное,
   что осталось перед этим тестом** — либо явное решение владельца
   переключить `runMachine:`'s ISO-гейт, либо изолированный тест
   `qemu_init()` с валидным argv отдельно от основного UI-флоу (см.
   пункт 2).

## Git

Последние важные commits (bridge wiring + argv/raster display, все на
agent/initial-a5vm):

    ea71a3d Wire A5VMQemuBridge into A5VMViewController
    798b983 Update handoff: argv builder and raster display mode done
    9dde5d2 Add +[A5VMQemuBridge argumentsWithRAMMegabytes:driveImagePath:isISO:]
    2215158 Add raster framebuffer mode to A5VMDisplayView
    af79d7d Update handoff: QEMU bridge compiles and links, not yet wired to UI
    15eb0ff Fix A5VMQemuBridge compile errors found by the first real build

QEMU iOS TLS/build fix chain (12 коммитов от 006502d до d6a66b4, см.
раздел QEMU выше):

    d6a66b4 Disable sin/cos builtin recognition, not just sincos
    bb04183 Match clang's builtin signature for __clear_cache
    4e8feb1 Resolve the last three link-time symbols (clear_cache/exp10/sincos)
    e916049 Link QEMU against libc++/libSystem explicitly
    9f3e005 Disable USB MTP passthrough, another pre-iOS10 SDK gap
    6b8dc6f Define VM_FLAGS_RANDOM_ADDR, another pre-SDK XNU constant
    4a212f4 Implement the missing ARM dcache flush for CONFIG_IOS_JIT
    cfb0800 Search the iPhoneOS SDK for libc++ headers before other platforms
    04b39cc Discover libc++ headers instead of guessing their path, add V=1
    ec9b92e Point libvixl's C++ build at the toolchain's own libc++ headers
    288bf7d Use sigaltstack coroutines, not the unported libucontext submodule
    67f1cbb Drop invalid --audio-drv-list=none for QEMU iOS configure
    f48530a Target iOS 9.0 for QEMU TLS, not generic Darwin
    006502d Keep QEMU LDFLAGS off the iOS TLS gate (fa3a4f6 continuation)

Более старые:

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

1. ~~Исправить QEMU ARMv7 iOS 6 TLS без unsafe глобальной подмены.~~ **Готово**
   (и заодно ещё 11 независимых build-багов после TLS, см. раздел QEMU).
2. ~~Получить QEMU dylib artifact и включить его в iOS package.~~ **Готово** —
   `ios-armv7` CI job зависит от `qemu-ios-armv7` и встраивает dylib/pc-bios
   в `A5VM.app` перед упаковкой. Ничего его пока не грузит/не вызывает.
3. ~~Сделать Objective-C/C bridge: dedicated pthread, lifecycle, VGA framebuffer,
   keyboard/scancode callback.~~ **Готово на уровне кода** (commit ea71a3d) —
   `app/A5VMQemuBridge.h/.m` полностью подключён к `A5VMViewController`
   (Run/Pause/Reset/Power/keyboard/textField), `A5VMDisplayView` умеет
   растровый режим. `_usesQemu` остаётся структурно недостижимым (см.
   "ObjC/C bridge" выше, пункт 2) — **НЕ проверено на устройстве**.
4. Переключить Windows ISO path на QEMU backend (снять/ослабить
   `runMachine:`'s "ISO needs QEMU" гейт) — единственный оставшийся шаг
   перед тем, как приоритет 3 станет реально используемым, а не только
   скомпилированным. Требует либо явного решения владельца, либо
   отдельного изолированного device-теста `qemu_init()`.
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

