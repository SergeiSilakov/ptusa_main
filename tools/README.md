# Упаковка приложения ACF (*.app) для AXC F 2000 EA

Всё необходимое для сборки и упаковки лежит в `ptusa_main`, внешние
репозитории не нужны.

Скрипт `package-acf-app.cmake` автоматизирует шаг «после сборки»: образ
контейнера и squashfs собираются **на контроллере** (`tools/mkapp-pac.sh`),
а готовый пакет раскладывается в `bin\apps` и
`bin\install\<устройство>\<конфигурация>\app`.

## Состав каталога

| Файл | Назначение |
|---|---|
| `mkapp-pac.sh` | упаковщик: копирует программу и библиотеки на контроллер, собирает образ (`podman import/tag`), пишет quadlet и манифест, пакует squashfs, забирает `bin\apps\<имя>-<версия>.app` |
| `package-acf-app.cmake` | обвязка: проверки, вызов упаковщика, раскладка пакета в `bin\install\<устройство>\<конфигурация>\app` |
| `package-acf-app.cmd` | запуск из консоли без CMake-пресета |
| `local-settings.cmake` | локальные адрес/ключ (не в git) |
| `local-settings.example.cmake` | образец локальных настроек |

## Как запускать

| Способ | Команда |
|---|---|
| из Visual Studio | цель **`acf_package`** в *CMake Targets View* → Build (рядом с `ptusa_main`, `install_app`) |
| из консоли CMake | `cmake --build --preset build-windows-AXCF2000EA-2026-LTS-Debug --target acf_package` |
| из проводника/консоли | `tools\package-acf-app.cmd [конфигурация] [версия] ["аргументы запуска"]` |

Примеры:

```cmd
tools\package-acf-app.cmd
tools\package-acf-app.cmd Debug 1.0.2
tools\package-acf-app.cmd Debug 1.0.2 "-d main.plua"
tools\package-acf-app.cmd Release 1.0.3
```

## Адрес контроллера: где менять

Адрес (и ключ) можно менять **перед каждым запуском** цели, не пересобирая
проект. Источники по убыванию приоритета:

1. **`-DHOST` / `-DKEY`** — то, что передаёт цель/пресет:
   `PTUSA_APP_HOST`, `PTUSA_APP_SSH_KEY` (кэш-переменные CMake);
2. **`tools\local-settings.cmake`** — локальный файл, **не в git**
   (образец: `tools\local-settings.example.cmake`). Правьте его перед
   запуском `acf_package` — реконфигурация не нужна;
3. **переменные окружения** `IOL_HOST`, `IOL_SSH_KEY` (или `IOL_SSH`/`IOL_SCP`);
4. значения по умолчанию.

Пример `tools\local-settings.cmake`:

```cmake
set(IOL_HOST "192.0.2.10")
set(IOL_SSH_KEY "$ENV{USERPROFILE}/.ssh/axcf.ppk")
```

Способы задать адрес разово:

```cmd
rem через .cmd (4-й аргумент)
tools\package-acf-app.cmd Release 1.0.3 "" 192.0.2.10

rem через кэш-переменную CMake (нужна реконфигурация)
cmake --preset build-windows-AXCF2000EA-2026-LTS-Debug -DPTUSA_APP_HOST=192.0.2.10

rem напрямую скриптом (в PowerShell -D с точками брать в кавычки)
cmake "-DCFG=Debug" "-DVERSION=1.0.2" "-DHOST=192.0.2.10" -P tools/package-acf-app.cmake
```

## Ключ SSH: как сделать (шаг за шагом)

Нужен один раз на рабочую машину: OpenSSH-клиент Windows (есть по умолчанию,
проверка `where ssh`) и пароль `admin` от контроллера — только на шаг 2.

### Шаг 1. Сгенерировать ключ

Выполнять в **cmd** (в PowerShell пустой аргумент `-N ""` теряется):

```cmd
ssh-keygen -t ed25519 -f %USERPROFILE%\.ssh\axcf_ed25519 -N "" -C "ptusa@axcf"
```

Появятся два файла в `%USERPROFILE%\.ssh`:

| Файл | Что это |
|---|---|
| `axcf_ed25519` | закрытый ключ — никому не передавать, в репозиторий не класть |
| `axcf_ed25519.pub` | публичный ключ — его и кладём на контроллер |

Парольная фраза не задаётся намеренно: упаковка запускается из VS/CMake без
интерактивного ввода. Если нужна passphrase — работать придётся через
`ssh-agent`, автоматизация усложнится.

### Шаг 2. Положить публичный ключ на контроллер (один раз)

```cmd
type %USERPROFILE%\.ssh\axcf_ed25519.pub | ssh admin@192.0.2.10 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Пароль `admin` спросится один раз. Альтернатива через WinSCP: зайти по паролю,
создать `/home/admin/.ssh` (права `700`), файл `authorized_keys` (права `600`)
и вставить в него строку из `.pub` — одной строкой, без переносов.

### Шаг 3. Проверить вход по ключу

```cmd
ssh -i %USERPROFILE%\.ssh\axcf_ed25519 -o BatchMode=yes admin@192.0.2.10 date
```

Ожидается дата контроллера и код возврата 0. При первом подключении ssh
спросит про host key — ответить `yes` (или добавить
`-o StrictHostKeyChecking=accept-new`).

### Шаг 4. Прописать в `tools\local-settings.cmake` (файл в `.gitignore`)

```cmake
file(TO_CMAKE_PATH "$ENV{USERPROFILE}" HOME_DIR)
set(IOL_HOST "admin@192.0.2.10")
set(IOL_SSH "ssh -i ${HOME_DIR}/.ssh/axcf_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=accept-new admin@192.0.2.10")
set(IOL_SCP "scp -i ${HOME_DIR}/.ssh/axcf_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=accept-new")
```

`file(TO_CMAKE_PATH ...)` нужен, чтобы путь был с прямыми слэшами — его
выполняет `sh`.

### Шаг 5. Проверить упаковкой

```cmd
cmake --build bin\build\AXCF2000EA_2026.0 --target acf_package
```

Признак успеха: `1. Копирую программу и библиотеки на контроллер`,
`2. Собираю образ и пакет на контроллере`, `Готово: ...bin\apps\ptusamain-<версия>.app`.

### Если нужен PuTTY (`plink`/`pscp`)

- `plink` 0.79 не читает OpenSSH-ключ нового формата (`Unable to use key file …
  (new format)`). Конвертировать в `.ppk`: **`puttygen` → Load → `axcf_ed25519`
  → Save private key**. В некоторых сборках CLI-конвертация молча ничего не
  делает — используйте именно GUI.
- Либо сгенерировать RSA в PEM: `ssh-keygen -t rsa -b 3072 -m PEM -f
  %USERPROFILE%\.ssh\axcf_rsa` — `plink` читает PEM.
- Тогда в `local-settings.cmake` достаточно
  `set(IOL_SSH_KEY "${HOME_DIR}/.ssh/axcf.ppk")`, а `IOL_SSH`/`IOL_SCP` не задавать.

### Частые ошибки

| Симптом | Причина | Что делать |
|---|---|---|
| `Permission denied (publickey)` | ключ не в `authorized_keys`, неверные права или не тот файл | повторить шаг 2, проверить `-i` и `ls -l ~/.ssh` на контроллере |
| `Unable to use key file … (new format)` | `plink` не понимает ed25519 OpenSSH | `.ppk` через `puttygen` (GUI) или работать через `ssh`/`scp` |
| `Host key verification failed` | нет записи в `known_hosts` | `ssh -o StrictHostKeyChecking=accept-new …` или `ssh-keygen -R <адрес>` |
| Упаковка «висит» на вопросе | ключ с passphrase | пересоздать ключ без пароля (шаг 1) |
| `mkdir: cannot create directory` на шаге 2 | нет прав в домашнем каталоге | заходить как `admin`, каталог `/home/admin` |

Закрытый ключ не копировать в репозиторий и на общие ресурсы; `.pub` — можно.
Отзыв/смена: удалить строку из `/home/admin/.ssh/authorized_keys`, повторить
шаги 1–4.

Реальные адреса и пути к ключам хранятся только в `tools\local-settings.cmake`
(не в git); в документации — заглушки (`192.0.2.10` — диапазон, зарезервированный
для примеров).

## Параметры подключения (окружение)

| Переменная | Назначение |
|---|---|
| `IOL_SDK` | каталог PLCnext SDK (по умолчанию `C:/CLI/sdks/AXCF2000EA/2026.0`) |
| `IOL_HOST` | адрес контроллера, например `192.0.2.10` |
| `IOL_SSH_KEY` | ключ PuTTY `*.ppk` |
| `IOL_SSH` / `IOL_SCP` | команды целиком (переопределяют `IOL_HOST`/`IOL_SSH_KEY`) |
| `IOL_IDENTIFIER` | идентификатор приложения, 14 цифр (по умолчанию `10000000000002`) |
| `IOL_EXEC_ARGS` | аргументы запуска в quadlet, например `-d main.plua` |
| `IOL_DRYRUN=1` | сухой прогон: `ssh`/`scp` заменяются на `echo`, пакет не создаётся |

Пароли и ключи в репозитории не хранятся.

## Что делает сценарий

1. проверяет бинарник (`bin\build\AXCF2000EA_2026.0\<Config>\ptusa_main`), SDK,
   `sh` (Git for Windows), формат версии (`<major>.<minor>.<patch>`, каждый ≤ 255);
2. вызывает `mkapp-pac.sh` — копирует программу и библиотеки на контроллер,
   собирает образ (`podman import`), пишет quadlet и `app_info.json`,
   пакует squashfs и забирает пакет в `apps\`;
3. копирует `apps\<имя>-<версия>.app` в `bin\apps` и в
   `bin\install\AXCF2000EA_26.0.4.13\<Config>\app`;
4. печатает путь пакета и напоминание про установку в WBM.

## Версия и аргументы запуска

Версия пакета — кэш-переменная `PTUSA_APP_VERSION` (по умолчанию `1.0.2`),
аргументы запуска — `PTUSA_APP_EXEC_ARGS`. Пресет
`build-windows-AXCF2000EA-2026-LTS-Debug` задаёт `-d main.plua`, поэтому
`acf_package` из Debug-сборки делает отладочный пакет. Переопределить можно
при конфигурации:

```cmd
cmake --preset build-windows-AXCF2000EA-2026-LTS-Debug -DPTUSA_APP_VERSION=1.0.3
```

## Автоупаковка после каждой сборки

```cmd
cmake --preset build-windows-AXCF2000EA-2026-LTS-Debug -DPTUSA_ACF_PACKAGE_AFTER_BUILD=ON
```

Тогда пакет собирается как POST_BUILD цели `ptusa_main`. По умолчанию
выключено: упаковка требует SSH и занимает время, её не всегда нужно делать
на каждом изменении.

## Ограничения

- без SSH-доступа к контроллеру пакет не собрать: образ и `mksquashfs`
  выполняются на устройстве (иначе теряются POSIX-права файлов образа);
- `bin\` в `.gitignore` — пакеты и бинарники в репозиторий не попадают;
- установка на контроллер — по-прежнему WBM → System → App management → Install.
