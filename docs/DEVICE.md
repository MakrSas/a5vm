# Установка и проверка на устройстве

Цель — iPhone 4S (`iPhone4,1`) с iOS 6.1.3 и jailbreak. Доступ по SSH под
root. Пароль в репозитории не хранится и храниться не должен.

Старым OpenSSH на устройстве нужен явно разрешённый алгоритм ключа:

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.0.109
```

## Установка

Артефакт CI `a5vm-ios6` содержит `A5VM.app`. Распаковать и залить:

```bash
scp -O -r A5VM.app root@192.168.0.109:/Applications/A5VM.app.new
```

Дальше подмена делается перемещением, а не записью поверх: если что-то
пойдёт не так, откат будет мгновенным.

```bash
ssh root@192.168.0.109 '
  rm -rf /Applications/A5VM.app.old
  [ -d /Applications/A5VM.app ] && mv /Applications/A5VM.app /Applications/A5VM.app.old
  mv /Applications/A5VM.app.new /Applications/A5VM.app
  chown -R mobile:mobile /Applications/A5VM.app
  chmod -R 755 /Applications/A5VM.app
  su mobile -c "uicache -p /Applications/A5VM.app"
'
```

Откат:

```bash
ssh root@192.168.0.109 '
  rm -rf /Applications/A5VM.app
  mv /Applications/A5VM.app.old /Applications/A5VM.app
  su mobile -c "uicache -p /Applications/A5VM.app"
'
```

## Проверка до запуска с иконки

Полноценно «нажать иконку» по SSH нельзя, но можно поймать ровно тот класс
ошибок, который сборка увидеть не в состоянии: загрузку библиотек на
настоящем устройстве и то, что выполняется в конструкторах до `main()`.

```bash
ssh root@192.168.0.109 \
  'su mobile -c "DYLD_PRINT_LIBRARIES=1 /Applications/A5VM.app/A5VM" 2>&1 | head -40'
```

Ожидаемое поведение: каждая зависимость найдена, процесс не падает и
остаётся висеть (без сессии SpringBoard `UIApplicationMain()` не
раскручивается до конца). Прервать по Ctrl-C.

Если приложение падает **до** появления окна, смотреть надо именно сюда:
успешная компоновка на сборочной машине ничего не говорит ни о наличии
файлов по записанным путям, ни о том, что конструкторы отработают на этом
конкретном ядре.

Проверить отдельно, что QEMU грузится и мост на месте:

```bash
ssh root@192.168.0.109 '
  otool -L /Applications/A5VM.app/libqemu-system-i386.dylib 2>/dev/null || \
    echo "otool на устройстве нет — проверяйте на сборочной стороне"
'
```

## Образы дисков

Приложение показывает в списке носителей всё, что лежит в
`/var/mobile/Documents` (для приложения из `/Applications` это и есть его
Documents). Расширения: `iso`, `img`, `bin` для CD и `img`, `ima`, `dsk`,
`vfd`, `flp` для дискет.

```bash
scp -O "Win98 SE (Boot Disk).img" root@192.168.0.109:/var/mobile/Documents/
ssh root@192.168.0.109 'chown mobile:mobile /var/mobile/Documents/*.img'
```

Права важны: приложение работает от имени `mobile` и файл, оставшийся за
`root`, откроется только на чтение — а для жёсткого диска нужна запись.

Образы самих машин лежат в `/var/mobile/Documents/Machines/<uuid>/`:
`config.plist` и разреженный `disk.img`.

## Ограничения, о которых стоит помнить при тестировании

* **Память.** iPhone 4S имеет 512 МБ физической памяти, и iOS 6 завершает
  процесс задолго до этой отметки. Гостевой размер ограничен 128 МБ, но
  разумный потолок для Windows 98 — 64 МБ.
* **Одна ВМ за запуск приложения — штатно, несколько — тоже.** Каждый пуск
  берёт свежую копию dylib, но копия эта весит около 15 МБ и пишется во
  временный каталог; десятки перезапусков подряд лучше чередовать с
  перезапуском приложения.
* **Сеть в госте отсутствует.** `--disable-slirp` в сборке; пользовательской
  сети нет вовсе.
* **Звука нет.** Ветка iOS в configure не оставляет ни одного аудиодрайвера.
