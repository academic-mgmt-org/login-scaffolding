#!/usr/bin/env bash

set -Eeuo pipefail

readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly INSTALLER="$ROOT/setup/install-interface-module.sh"
readonly NOTIFICATIONS_INSTALLER="$ROOT/setup/install-notifications-interface.sh"
readonly RUNTIME="$ROOT/setup/prepare-interface-runtime.sh"
readonly PLUGGABLE_PATCH="$ROOT/patches/0002-pluggable-modules.patch"
readonly NOTIFICATIONS_UI_PATCH="$ROOT/patches/0601-academico-notificaciones-ui.patch"
readonly LOCK_DIR="$ROOT/locks"

declare -A PATCHES=(
    [academico-login]='0100-academico-login.patch'
    [academico-usuarios]='0200-academico-usuarios.patch'
    [academico-matriculas]='0300-academico-matriculas.patch'
    [academico-calificaciones]='0400-academico-calificaciones.patch'
    [academico-solicitudes]='0500-academico-solicitudes.patch'
    [academico-notificaciones]='0600-academico-notificaciones.patch'
)

declare -A DOMAINS=(
    [academico-login]='auth'
    [academico-usuarios]='usuarios'
    [academico-matriculas]='matriculas'
    [academico-calificaciones]='calificaciones'
    [academico-solicitudes]='solicitudes'
    [academico-notificaciones]='notificaciones'
)

bash -n "$INSTALLER"
bash -n "$NOTIFICATIONS_INSTALLER"
bash -n "$RUNTIME"

if ! grep -Fq 'docker compose exec -T laravel.test npm run build' "$NOTIFICATIONS_INSTALLER"; then
    printf 'ERROR: el modo adjunto debe recompilar los estilos de la interfaz gráfica.\n' >&2
    exit 1
fi

if [[ ! -x "$NOTIFICATIONS_INSTALLER" ]]; then
    printf 'ERROR: el instalador plugable de Notificaciones no es ejecutable.\n' >&2
    exit 1
fi

if [[ ! -f "$PLUGGABLE_PATCH" ]] || ! grep -Fq 'class AcademicModules' "$PLUGGABLE_PATCH"; then
    printf 'ERROR: falta la capa de registro de módulos plugables.\n' >&2
    exit 1
fi

if [[ ! -f "$NOTIFICATIONS_UI_PATCH" ]] \
    || ! grep -Fq 'class AcademicNotificationController' "$NOTIFICATIONS_UI_PATCH" \
    || ! grep -Fq 'data-test="notifications-inbox"' "$NOTIFICATIONS_UI_PATCH"; then
    printf 'ERROR: falta la bandeja gráfica para el usuario final de Notificaciones.\n' >&2
    exit 1
fi

if ! grep -Fq \
    'generate_if_missing app/Contracts/AcademicGateway.php make:interface Contracts/AcademicGateway' \
    "$INSTALLER"; then
    printf 'ERROR: el stub de AcademicGateway debe generarse dentro de app/Contracts.\n' >&2
    exit 1
fi

login_action="$(grep -F "'validate_session' =>" "$ROOT/patches/0100-academico-login.patch")"
if [[ "$login_action" != *"'rpc' => 'auth.v1.AuthService/ValidateToken'"* \
    || "$login_action" != *"'access_token_field' => 'token'"* ]]; then
    printf 'ERROR: la validación de sesión debe usar ValidateToken con el token de la sesión.\n' >&2
    exit 1
fi

notifications_list_action="$(grep -F "'list_unread' =>" "$ROOT/patches/0600-academico-notificaciones.patch")"
if [[ "$notifications_list_action" != *"'estado' => 'no_leido'"* ]] \
    || [[ "$notifications_list_action" == *"'estado' => 'no_leida'"* ]]; then
    printf 'ERROR: ListNotifications debe usar el estado contractual no_leido.\n' >&2
    exit 1
fi

for legacy_path in \
    package.json \
    package-lock.json \
    templates \
    patches/0001-gateway-client.patch \
    patches/0002-fortify-login-flow.patch \
    patches/0003-tests-and-analysis.patch \
    patches/0004-disable-test-timeout.patch \
    patches/0005-academic-gateway-interfaces.patch \
    patches/0006-deterministic-tailwind-source.patch \
    setup/install-login-test-dependencies.sh \
    setup/normalize-generated-app.sh \
    setup/verify-generated-app.sh; do
    if [[ -e "$ROOT/$legacy_path" ]]; then
        printf 'ERROR: todavía existe el artefacto monolítico %s.\n' "$legacy_path" >&2
        exit 1
    fi
done

for lock_file in composer.lock package-lock.json; do
    if [[ ! -f "$LOCK_DIR/$lock_file" ]]; then
        printf 'ERROR: falta el lock reproducible %s.\n' "$LOCK_DIR/$lock_file" >&2
        exit 1
    fi
done

if [[ -e "$ROOT/patches/modular" ]]; then
    printf 'ERROR: todavía existe la antigua carpeta patches/modular.\n' >&2
    exit 1
fi

if find "$ROOT/patches" -mindepth 2 -type f -name '*.patch' | grep -q .; then
    printf 'ERROR: los parches deben estar directamente en patches/.\n' >&2
    exit 1
fi

if find "$ROOT/tests" -maxdepth 1 -type f -name '*.js' | grep -q .; then
    printf 'ERROR: todavía existen pruebas E2E de la aplicación monolítica.\n' >&2
    exit 1
fi

if grep -q 'config/academic-module.php' "$ROOT/patches/0001-interface-core.patch"; then
    printf 'ERROR: el parche común no puede seleccionar un módulo.\n' >&2
    exit 1
fi

for module in "${!PATCHES[@]}"; do
    output="$($INSTALLER "$module" /tmp/example-academic-interface --plan)"

    grep -Fq "MÓDULO: $module" <<<"$output"
    grep -Fq "PARCHE DEL MÓDULO: $ROOT/patches/${PATCHES[$module]}" <<<"$output"
    grep -Fq "PARCHE PLUGABLE: $PLUGGABLE_PATCH" <<<"$output"
    grep -Fq 'CONTRATO TÉCNICO: academico-login@' <<<"$output"
    grep -Fq "CLIENTES GENERADOS: auth$([[ "${DOMAINS[$module]}" == auth ]] && printf '' || printf ' + %s' "${DOMAINS[$module]}")" <<<"$output"

    if [[ "$module" == academico-notificaciones ]]; then
        grep -Fq "INTERFAZ DE USUARIO: $NOTIFICATIONS_UI_PATCH" <<<"$output"
    fi

    if [[ "$module" == academico-login ]]; then
        if grep -q 'CONTRATO FUNCIONAL ÚNICO:' <<<"$output"; then
            printf 'ERROR: academico-login intentó añadir otro contrato.\n' >&2
            exit 1
        fi
    else
        grep -Fq "CONTRATO FUNCIONAL ÚNICO: $module@" <<<"$output"
    fi

    module_patch="$ROOT/patches/${PATCHES[$module]}"
    changed_files="$(sed -n 's|^diff --git a/[^ ]* b/||p' "$module_patch")"

    if [[ "$changed_files" != "config/academic-modules/$module.php" ]]; then
        printf 'ERROR: %s no está aislado en config/academic-modules/.\n' "$module_patch" >&2
        exit 1
    fi

    test -f "$ROOT/docs/$module.md"
    grep -Fq "$module" "$ROOT/docs/$module.md"
done

notification_ui_files="$(sed -n 's|^diff --git a/[^ ]* b/||p' "$NOTIFICATIONS_UI_PATCH")"
for expected_ui_file in \
    app/Http/Controllers/AcademicNotificationController.php \
    config/academic-presentations.php \
    resources/views/academic-interface/notifications.blade.php; do
    if ! grep -Fxq "$expected_ui_file" <<<"$notification_ui_files"; then
        printf 'ERROR: la interfaz gráfica no instala %s.\n' "$expected_ui_file" >&2
        exit 1
    fi
done

grep -Fq 'Los nombres de RPC' "$ROOT/docs/academico-notificaciones.md"
grep -Fq '/academico/notificaciones' "$ROOT/docs/academico-notificaciones.md"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

standalone_plan="$(WORK_ROOT="$fixture_root" "$NOTIFICATIONS_INSTALLER" --plan --standalone)"
grep -Fq 'MODO: interfaz autónoma de Notificaciones' <<<"$standalone_plan"
grep -Fq "$fixture_root/interfaz-academico-notificaciones" <<<"$standalone_plan"

login_fixture="$fixture_root/interfaz-academico-login"
mkdir -p "$login_fixture/config"
: > "$login_fixture/artisan"
: > "$login_fixture/composer.json"
printf "%s\n" "<?php return ['key' => 'academico-login'];" > "$login_fixture/config/academic-module.php"

attached_plan="$(WORK_ROOT="$fixture_root" "$NOTIFICATIONS_INSTALLER" --plan)"
grep -Fq 'MODO: adjuntar al host Login' <<<"$attached_plan"
grep -Fq "HOST_APP_DIR: $login_fixture" <<<"$attached_plan"

printf 'OK: los seis módulos son acumulativos y Notificaciones resuelve host o modo autónomo.\n'
