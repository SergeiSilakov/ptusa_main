# Упаковка приложения ACF (*.app) для AXC F 2000 EA.
#
# Образ и squashfs собираются НА КОНТРОЛЛЕРЕ скриптом
# tools/mkapp-pac.sh (лежит рядом, внешних репозиториев не требует),
# поэтому нужен SSH-доступ. Готовый пакет кладётся в bin/apps и
# bin/install/<устройство>/<конфигурация>/app.
#
# Запуск (обычно через цель acf_package, но можно и вручную; значения -D
# с точками обязательно брать в кавычки из PowerShell):
#   cmake "-DCFG=Debug" "-DVERSION=1.0.2" "-DHOST=192.0.2.10" ^
#         "-DBUILD_DIR=P:/ptusa_main/bin/build/AXCF2000EA_2026.0" ^
#         -P P:/ptusa_main/tools/package-acf-app.cmake
#
# Источники параметров (по убыванию приоритета):
#   1) -D<ИМЯ>=... в командной строке (пресет/цель задают -DHOST/-DKEY);
#   2) tools/local-settings.cmake — локальный файл, НЕ в git:
#      set(IOL_HOST "..."), set(IOL_SSH_KEY "..."), set(IOL_SDK "...") и т.д.;
#   3) переменные окружения IOL_HOST, IOL_SSH_KEY, IOL_SSH, IOL_SCP,
#      IOL_SDK, IOL_IDENTIFIER, IOL_EXEC_ARGS, IOL_DRYRUN;
#   4) значения по умолчанию.
#
# Пароли и ключи в репозитории не хранятся.

cmake_minimum_required(VERSION 3.21)

# Локальные настройки машины/объекта (адрес контроллера, ключ, SDK).
# Файл необязательный и игнорируется git — его можно править перед
# запуском цели acf_package, переконфигурация CMake не нужна.
include("${CMAKE_CURRENT_LIST_DIR}/local-settings.cmake" OPTIONAL)

# --- параметры -------------------------------------------------------------
if(NOT DEFINED CFG OR CFG STREQUAL "")
    set(CFG Debug)
endif()
if(NOT DEFINED NAME OR NAME STREQUAL "")
    set(NAME "ptusamain")
endif()
if(NOT DEFINED VERSION OR VERSION STREQUAL "")
    set(VERSION "1.0.2")
endif()
if(NOT DEFINED EXEC_ARGS OR EXEC_ARGS STREQUAL "")
    if(DEFINED IOL_EXEC_ARGS AND NOT IOL_EXEC_ARGS STREQUAL "")
        set(EXEC_ARGS "${IOL_EXEC_ARGS}")
    else()
        set(EXEC_ARGS "$ENV{IOL_EXEC_ARGS}")
    endif()
endif()
if(EXEC_ARGS STREQUAL "")
    set(EXEC_ARGS "main.plua")
endif()

get_filename_component(SRC "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

if(NOT DEFINED BUILD_DIR OR BUILD_DIR STREQUAL "")
    set(BUILD_DIR "${SRC}/bin/build/AXCF2000EA_2026.0")
endif()
if(NOT DEFINED BINARY OR BINARY STREQUAL "")
    set(BINARY "${BUILD_DIR}/${CFG}/ptusa_main")
endif()

if(NOT DEFINED SDK OR SDK STREQUAL "")
    if(DEFINED IOL_SDK AND NOT IOL_SDK STREQUAL "")
        set(SDK "${IOL_SDK}")
    else()
        set(SDK "$ENV{IOL_SDK}")
    endif()
endif()
if(SDK STREQUAL "")
    set(SDK "C:/CLI/sdks/AXCF2000EA/2026.0")
endif()

if(NOT DEFINED IDENTIFIER OR IDENTIFIER STREQUAL "")
    if(DEFINED IOL_IDENTIFIER AND NOT IOL_IDENTIFIER STREQUAL "")
        set(IDENTIFIER "${IOL_IDENTIFIER}")
    else()
        set(IDENTIFIER "$ENV{IOL_IDENTIFIER}")
    endif()
endif()
if(IDENTIFIER STREQUAL "")
    set(IDENTIFIER "10000000000002")
endif()

set(APP_TARGET "$ENV{IOL_TARGET}")
if(APP_TARGET STREQUAL "")
    set(APP_TARGET "AXC F 2000 EA")
endif()
set(FIRMWARE "$ENV{IOL_FIRMWARE}")
if(FIRMWARE STREQUAL "")
    set(FIRMWARE "26.0.0")
endif()
set(DEVICE_DIR "AXCF2000EA_26.0.4.13")

# --- проверки --------------------------------------------------------------
if(NOT EXISTS "${BINARY}")
    message(FATAL_ERROR "Не найден бинарник: ${BINARY}. "
        "Соберите цель ptusa_main для конфигурации ${CFG}.")
endif()

if(NOT VERSION MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)$")
    message(FATAL_ERROR "Версия должна быть <major>.<minor>.<patch>, "
        "например 1.0.2 (получено '${VERSION}').")
endif()
foreach(part ${CMAKE_MATCH_1} ${CMAKE_MATCH_2} ${CMAKE_MATCH_3})
    if(part GREATER 255)
        message(FATAL_ERROR "Каждый компонент версии должен быть <= 255 "
            "(получено '${VERSION}').")
    endif()
endforeach()

if(NOT EXISTS "${SRC}/tools/mkapp-pac.sh")
    message(FATAL_ERROR "Не найден упаковщик: ${SRC}/tools/mkapp-pac.sh")
endif()
if(NOT EXISTS "${SDK}/toolchain.cmake")
    message(FATAL_ERROR "Не найден PLCnext SDK: ${SDK} (задайте IOL_SDK).")
endif()

# --- sh --------------------------------------------------------------------
set(SH "")
foreach(candidate "C:/Program Files/Git/bin/sh.exe"
        "C:/Program Files/Git/usr/bin/sh.exe")
    if(EXISTS "${candidate}")
        set(SH "${candidate}")
        break()
    endif()
endforeach()
if(SH STREQUAL "")
    find_program(SH NAMES sh.exe sh)
endif()
if(SH STREQUAL "" OR NOT EXISTS "${SH}")
    message(FATAL_ERROR "Не найден sh.exe (нужен Git for Windows).")
endif()

# --- ssh/scp ---------------------------------------------------------------
if(NOT DEFINED HOST OR HOST STREQUAL "")
    if(DEFINED IOL_HOST AND NOT IOL_HOST STREQUAL "")
        set(HOST "${IOL_HOST}")
    else()
        set(HOST "$ENV{IOL_HOST}")
    endif()
endif()
if(NOT DEFINED KEY OR KEY STREQUAL "")
    if(DEFINED IOL_SSH_KEY AND NOT IOL_SSH_KEY STREQUAL "")
        set(KEY "${IOL_SSH_KEY}")
    else()
        set(KEY "$ENV{IOL_SSH_KEY}")
    endif()
endif()
if(NOT DEFINED SSH OR SSH STREQUAL "")
    if(DEFINED IOL_SSH AND NOT IOL_SSH STREQUAL "")
        set(SSH "${IOL_SSH}")
    else()
        set(SSH "$ENV{IOL_SSH}")
    endif()
endif()
if(NOT DEFINED SCP OR SCP STREQUAL "")
    if(DEFINED IOL_SCP AND NOT IOL_SCP STREQUAL "")
        set(SCP "${IOL_SCP}")
    else()
        set(SCP "$ENV{IOL_SCP}")
    endif()
endif()

if("$ENV{IOL_DRYRUN}" STREQUAL "1")
    set(SSH "echo")
    set(SCP "echo")
    message(STATUS "СУХОЙ ПРОГОН: ssh/scp заменены на echo, пакет не создаётся.")
else()
    if(SSH STREQUAL "" OR SCP STREQUAL "")
        if(HOST STREQUAL "")
            message(FATAL_ERROR "Не задан адрес контроллера: укажите -DHOST, "
                "IOL_HOST в tools/local-settings.cmake или переменную окружения.")
        endif()
        if(KEY STREQUAL "" OR NOT EXISTS "${KEY}")
            message(FATAL_ERROR "Не задан ключ: -DKEY, IOL_SSH_KEY в "
                "tools/local-settings.cmake или IOL_SSH/IOL_SCP.")
        endif()
        set(SSH "plink -ssh -batch -i \"${KEY}\" admin@${HOST}")
        set(SCP "pscp -batch -i \"${KEY}\"")
    endif()
endif()

# --- окружение упаковщика --------------------------------------------------
set(ENV{IOL_SDK} "${SDK}")
set(ENV{IOL_SSH} "${SSH}")
set(ENV{IOL_SCP} "${SCP}")
if(NOT HOST STREQUAL "")
    set(ENV{IOL_HOST} "${HOST}")
endif()
set(ENV{IOL_IDENTIFIER} "${IDENTIFIER}")
set(ENV{IOL_EXEC_ARGS} "${EXEC_ARGS}")
set(ENV{IOL_TARGET} "${APP_TARGET}")
set(ENV{IOL_FIRMWARE} "${FIRMWARE}")
set(ENV{IOL_NAME} "${NAME}")

file(TO_CMAKE_PATH "${BINARY}" BINARY_POSIX)

message(STATUS "Бинарник:      ${BINARY}")
message(STATUS "Версия:        ${VERSION}")
message(STATUS "SDK:           ${SDK}")
if(NOT HOST STREQUAL "")
    message(STATUS "Адрес:         ${HOST}")
endif()
if(NOT KEY STREQUAL "")
    message(STATUS "Ключ:          ${KEY}")
endif()
message(STATUS "SSH:           ${SSH}")
message(STATUS "Идентификатор: ${IDENTIFIER}")
message(STATUS "Exec:          ${EXEC_ARGS}")

# --- упаковка --------------------------------------------------------------
# Упаковщик лежит рядом (tools/mkapp-pac.sh) и пишет пакет в bin/apps.
execute_process(
    COMMAND "${SH}" "tools/mkapp-pac.sh" "${BINARY_POSIX}" "${VERSION}"
    WORKING_DIRECTORY "${SRC}"
    RESULT_VARIABLE packResult)
if(NOT packResult EQUAL 0)
    message(FATAL_ERROR "Упаковщик завершился с кодом ${packResult}.")
endif()

if("$ENV{IOL_DRYRUN}" STREQUAL "1")
    message(STATUS "Сухой прогон завершён: параметры и команды корректны.")
    return()
endif()

set(APP "${SRC}/bin/apps/${NAME}-${VERSION}.app")
if(NOT EXISTS "${APP}")
    message(FATAL_ERROR "Пакет не создан: ${APP}")
endif()

# --- раскладка -------------------------------------------------------------
set(INSTALL_DIR "${SRC}/bin/install/${DEVICE_DIR}/${CFG}/app")
file(MAKE_DIRECTORY "${INSTALL_DIR}")
file(COPY_FILE "${APP}" "${INSTALL_DIR}/${NAME}-${VERSION}.app" ONLY_IF_DIFFERENT)

file(SIZE "${APP}" appSize)
math(EXPR appSizeMb "${appSize} / 1048576")
message(STATUS "")
message(STATUS "Готово: ${INSTALL_DIR}/${NAME}-${VERSION}.app (${appSizeMb} МБ)")
message(STATUS "Дальше: WBM -> System -> App management -> Install -> выбрать файл -> Start.")
