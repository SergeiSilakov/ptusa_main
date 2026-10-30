#!/bin/sh
# Упаковка управляющей программы ptusa_main в приложение контроллера (ACF).
#
# Скрипт самодостаточный: живёт в ptusa_main, ничего не берёт из других
# репозиториев. Образ и пакет собираются НА КОНТРОЛЛЕРЕ (у файлов образа
# должны быть POSIX-права, локальный mksquashfs на Windows их теряет).
#
# Применение:
#     sh tools/mkapp-pac.sh <бинарник> <версия> [каталог проекта]
#
# Обычно вызывается из цели CMake acf_package (см. tools/README.md):
#     cmake --build <каталог сборки> --target acf_package
#
# Что делает:
#   1. копирует программу и библиотеки набора SDK на контроллер;
#   2. собирает образ на контроллере (podman import + tag);
#   3. проверяет образ запуском (`-h`) до упаковки;
#   4. пишет quadlet и манифест, пакует squashfs;
#   5. забирает пакет в bin/apps/<имя>-<версия>.app.
#
# Переменные окружения:
#     IOL_SDK          каталог PLCnext SDK (обязательно)
#     IOL_SSH          команда SSH с адресом и ключом (обязательно)
#     IOL_SCP          команда копирования без адреса (обязательно)
#     IOL_HOST         адрес контроллера в виде admin@<адрес> (обязательно)
#     IOL_IDENTIFIER   идентификатор приложения, ровно 14 цифр (обязательно)
#     IOL_EXEC_ARGS    аргументы запуска в quadlet (по умолчанию main.plua)
#     IOL_PROJECT_DIR  каталог проекта на контроллере (/home/admin/main)
#     IOL_NAME         имя приложения (по умолчанию ptusamain)
#     IOL_TARGET       имя контроллера как в WBM (AXC F 2000 EA)
#     IOL_FIRMWARE     минимальная прошивка во внутреннем формате (26.0.0)
#
# Пароли и ключи в скрипте не хранятся: они входят в IOL_SSH и IOL_SCP.

set -e

BINARY=${1:-}
VERSION=${2:-}
PROJECT_DIR=${3:-${IOL_PROJECT_DIR:-/home/admin/main}}

NAME=${IOL_NAME:-ptusamain}
IDENTIFIER=${IOL_IDENTIFIER:-}
TARGET=${IOL_TARGET:-AXC F 2000 EA}
FIRMWARE=${IOL_FIRMWARE:-26.0.0}
SDK=${IOL_SDK:-}
SSH=${IOL_SSH:-}
SCP=${IOL_SCP:-}
HOST=${IOL_HOST:-}
# Аргументы запуска программы в приложении (Exec= в quadlet).
# Для отладочного запуска: IOL_EXEC_ARGS='-d main.plua'.
EXEC_ARGS=${IOL_EXEC_ARGS:-main.plua}

usage()
    {
    echo 'Применение: sh tools/mkapp-pac.sh <бинарник> <версия> [каталог проекта]'
    echo 'Задайте IOL_SDK, IOL_SSH, IOL_SCP, IOL_HOST, IOL_IDENTIFIER — см. tools/README.md'
    }

if [ -z "$BINARY" ] || [ -z "$VERSION" ] || [ ! -f "$BINARY" ]; then
    usage
    exit 1
fi
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
    echo 'Не задан IOL_SDK (каталог PLCnext SDK).'
    exit 1
fi
if [ -z "$SSH" ] || [ -z "$SCP" ]; then
    echo 'Не заданы IOL_SSH и IOL_SCP (команды подключения к контроллеру).'
    exit 1
fi
if [ -z "$IDENTIFIER" ]; then
    echo 'Не задан IOL_IDENTIFIER (14 цифр).'
    exit 1
fi

LIBS="$SDK/sysroots/cortexa53-crypto-pxc-linux/usr/lib"
if [ ! -d "$LIBS" ]; then
    echo 'В SDK нет каталога sysroots/cortexa53-crypto-pxc-linux/usr/lib.'
    exit 1
fi

WORK=bin/build/app/$NAME-$VERSION
OUT=bin/apps
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"

echo '1. Копирую программу и библиотеки на контроллер'
$SCP "$BINARY" "$HOST:/tmp/$NAME"
for lib in ld-linux-aarch64.so.1 libc.so.6 libm.so.6 libstdc++.so.6 \
    libgcc_s.so.1; do
    if [ -f "$LIBS/$lib" ]; then
        $SCP "$LIBS/$lib" "$HOST:/tmp/$lib" >/dev/null
    else
        echo '   нет библиотеки: '"$lib"
    fi
done

echo '2. Собираю образ и пакет на контроллере'
cat >"$WORK/pack.sh" <<PACK
set -e
rm -rf /tmp/${NAME}-img /tmp/${NAME}-app
mkdir -p /tmp/${NAME}-img/lib /tmp/${NAME}-img/usr/lib /tmp/${NAME}-img/etc
mkdir -p /tmp/${NAME}-app
cp /tmp/$NAME /tmp/${NAME}-img/$NAME
chmod 755 /tmp/${NAME}-img/$NAME
for lib in ld-linux-aarch64.so.1 libc.so.6 libm.so.6 libstdc++.so.6 libgcc_s.so.1; do
    cp /tmp/\$lib /tmp/${NAME}-img/lib/\$lib 2>/dev/null || true
    cp /tmp/\$lib /tmp/${NAME}-img/usr/lib/\$lib 2>/dev/null || true
done
#Загрузчику нужно право исполнения: без него ядро не запустит программу
chmod 755 /tmp/${NAME}-img/lib/ld-linux-aarch64.so.1 \
    /tmp/${NAME}-img/usr/lib/ld-linux-aarch64.so.1
printf 'nameserver 127.0.0.1\n' > /tmp/${NAME}-img/etc/resolv.conf
tar -cf /tmp/${NAME}-img.tar -C /tmp/${NAME}-img .
podman rmi -f ${NAME}:$VERSION localhost/${NAME}:$VERSION >/dev/null 2>&1 || true
podman import --change 'ENTRYPOINT ["/$NAME"]' /tmp/${NAME}-img.tar ${NAME}:$VERSION >/dev/null 2>&1
podman tag ${NAME}:$VERSION localhost/${NAME}:$VERSION
podman save --format oci-archive -o /tmp/${NAME}-app/${NAME}-oci.tar \
    localhost/${NAME}:$VERSION >/dev/null 2>&1
ID=\$(podman image inspect localhost/${NAME}:$VERSION --format '{{.Id}}' | cut -c1-12)
cat > /tmp/${NAME}-app/${NAME}.container <<EOF
[Unit]
Description=${NAME}

[Container]
Image=localhost/${NAME}:$VERSION
Network=host
WorkingDir=/main
Exec=$EXEC_ARGS
Volume=$PROJECT_DIR:/main:Z
Volume=${NAME}-data:/data

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF
cat > /tmp/${NAME}-app/app_info.json <<EOF
{
  "plcnextapp": {
    "name": "$NAME",
    "identifier": "$IDENTIFIER",
    "version": "$VERSION.0",
    "target": "$TARGET",
    "minfirmware_version": "$FIRMWARE",
    "manufacturer": "PTUSA",
    "licensetype": "Free"
  },
  "datastorage": { "persistentdata": true, "temporarydata": true },
  "ocicontainer": {
    "images": [ { "id": "\$ID", "name": "$NAME", "path": "$NAME-oci.tar" } ],
    "environmentVariables": [],
    "quadletFiles": [ { "path": "$NAME.container", "type": "Main" } ]
  }
}
EOF
echo '   проверка образа запуском:'
podman run --rm localhost/${NAME}:$VERSION -h 2>&1 | head -3 || true
rm -f /tmp/$NAME.app
mksquashfs /tmp/${NAME}-app /tmp/$NAME.app -comp gzip -b 131072 -noappend >/dev/null 2>&1
ls -la /tmp/$NAME.app
PACK

$SCP "$WORK/pack.sh" "$HOST:/tmp/${NAME}-pack.sh" >/dev/null
$SSH "sh /tmp/${NAME}-pack.sh"
$SCP "$HOST:/tmp/$NAME.app" "$OUT/$NAME-$VERSION.app"

echo '3. Готово: '"$OUT/$NAME-$VERSION.app"
echo '   Установка: WBM → System → App management → Install.'
echo '   Проект на контроллере: '"$PROJECT_DIR"
