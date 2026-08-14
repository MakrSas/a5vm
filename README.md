# A5VM

QEMU для jailbroken iPhone 4S на iOS 6.1 — приложение в духе UTM,
с интерфейсом, собранным целиком из стандартных компонентов UIKit iOS 6.

* **Цель устройства:** iPhone 4S (`iPhone4,1`), ARMv7, iOS 6.1.3, jailbreak.
* **Гость:** `i386-softmmu` — DOS, Windows 95/98.
* **Бэкенд:** QEMU 5.1 (форк UTM с поддержкой iOS), собранный как
  `libqemu-system-i386.dylib` и загружаемый в тот же процесс, что и UI.
* **Сборка:** GitHub Actions, runner `macos-latest` + SDK iPhoneOS 6.1.
  Локальный macOS не нужен.

## Структура

```
app/                    iOS-приложение (Objective-C, UIKit, ARC)
bridge/                 C-мост между QEMU и приложением
  a5_qemu.h             стабильный ABI, единственное, что видит приложение
  a5_qemu.c             компилируется ВНУТРИ дерева QEMU, с его заголовками
scripts/
  ios-env.sh            общие настройки тулчейна armv7/iOS 6
  fetch-sdk.sh          загрузка iPhoneOS6.1.sdk
  build-deps.sh         кросс-сборка glib, pixman, libffi, pcre2 (статически)
  build-qemu.sh         кросс-сборка libqemu-system-i386.dylib
  build-app.sh          сборка A5VM.app (clang напрямую, без theos)
  compat/               заглушки для того, чего нет в SDK 6.1
.github/workflows/      CI
docs/                   заметки по портированию и по устройству
```

## Установка на устройство

Артефакт CI (`a5vm-ios6`) содержит готовый `A5VM.app`. На устройстве:

```
scp -r A5VM.app root@<ip>:/Applications/
ssh root@<ip> 'chown -R mobile:mobile /Applications/A5VM.app && \
  chmod -R 755 /Applications/A5VM.app && \
  su mobile -c "uicache -p /Applications/A5VM.app"'
```

Образы дисков кладутся в `/var/mobile/Documents` — приложение показывает
их в списке носителей.

## Лицензия

QEMU распространяется под GPL-2.0; собранная библиотека и всё, что с ней
слинковано, наследуют эти условия. Копия лицензии кладётся в бандл как
`QEMU-COPYING`.
