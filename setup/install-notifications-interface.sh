#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCAFFOLDING_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly LIVEWIRE_STARTER_DEFAULT='laravel/livewire-starter-kit:dev-main#1f84e33e6bf6c95f9925e3e023bce71341ced005'

plan=false
skip_dependencies=false
force_standalone=false

usage() {
    cat <<'USAGE'
Uso:
  install-notifications-interface.sh [--plan] [--standalone] [--skip-dependencies]

Comportamiento:
  1. Si encuentra una aplicación academico-login, añade Notificaciones a ese
     mismo APP_DIR y reutiliza su compose.yaml y su sesión.
  2. Si no encuentra el host, crea una aplicación autónoma de Notificaciones
     que incluye el núcleo Auth/Login y levanta su propio compose.yaml.

Variables:
  WORK_ROOT              Raíz común de interfaces.
  LOGIN_APP_DIR          Host Login explícito; desactiva la autodetección.
  LOGIN_APP_NAME         Nombre del host dentro de WORK_ROOT.
  NOTIFICATIONS_APP_DIR  Aplicación autónoma explícita.
  APP_NAME               Nombre autónomo dentro de WORK_ROOT.
  LIVEWIRE_STARTER       Revisión del Starter Kit.

Opciones:
  --standalone           Ignora hosts Login y crea/actualiza el frontend propio.
  --skip-dependencies    Omite la preparación global de herramientas del host.
USAGE
}

while (($# > 0)); do
    case "$1" in
        --plan) plan=true ;;
        --standalone) force_standalone=true ;;
        --skip-dependencies) skip_dependencies=true ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: opción desconocida: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

default_work_root="$(cd -- "$SCAFFOLDING_DIR/.." && pwd)/interfaces-academicas"
work_root="${WORK_ROOT:-$default_work_root}"
login_app_name="${LOGIN_APP_NAME:-interfaz-academico-login}"
notifications_app_name="${APP_NAME:-interfaz-academico-notificaciones}"
livewire_starter="${LIVEWIRE_STARTER:-$LIVEWIRE_STARTER_DEFAULT}"

is_laravel_app() {
    [[ -f "$1/artisan" && -f "$1/composer.json" ]]
}

is_login_host() {
    local candidate="$1"

    is_laravel_app "$candidate" || return 1

    [[ -f "$candidate/config/academic-modules/academico-login.php" ]] ||
        grep -Fq "'key' => 'academico-login'" "$candidate/config/academic-module.php" 2>/dev/null
}

canonical_directory() {
    (cd -- "$1" && pwd)
}

login_app_dir=''
if $force_standalone; then
    :
elif [[ -n "${LOGIN_APP_DIR:-}" ]]; then
    if ! is_login_host "$LOGIN_APP_DIR"; then
        printf 'ERROR: LOGIN_APP_DIR no contiene una interfaz academico-login: %s\n' "$LOGIN_APP_DIR" >&2
        exit 1
    fi

    login_app_dir="$(canonical_directory "$LOGIN_APP_DIR")"
else
    declare -a candidates=(
        "$work_root/$login_app_name"
        "$HOME/interfaces-academicas/$login_app_name"
    )
    declare -a detected_hosts=()

    for candidate in "${candidates[@]}"; do
        if is_login_host "$candidate"; then
            canonical="$(canonical_directory "$candidate")"
            already_detected=false

            for detected in "${detected_hosts[@]}"; do
                if [[ "$detected" == "$canonical" ]]; then
                    already_detected=true
                    break
                fi
            done

            if ! $already_detected; then
                detected_hosts+=("$canonical")
            fi
        fi
    done

    if ((${#detected_hosts[@]} > 1)); then
        printf 'ERROR: se encontraron varios hosts Login; defina LOGIN_APP_DIR explícitamente:\n' >&2
        printf '  %s\n' "${detected_hosts[@]}" >&2
        exit 1
    fi

    if ((${#detected_hosts[@]} == 1)); then
        login_app_dir="${detected_hosts[0]}"
    fi
fi

if [[ -n "$login_app_dir" ]]; then
    printf 'MODO: adjuntar al host Login\n'
    printf 'HOST_APP_DIR: %s\n' "$login_app_dir"
    printf 'INTERFAZ GRÁFICA: /academico/notificaciones\n'

    if $plan; then
        exit 0
    fi

    if ! $skip_dependencies; then
        "$SCRIPT_DIR/install-interface-dependencies.sh"
    fi

    installer_options=(--skip-dependencies)
    "$SCRIPT_DIR/install-interface-module.sh" \
        academico-notificaciones \
        "$login_app_dir" \
        "${installer_options[@]}"

    if [[ -f "$login_app_dir/compose.yaml" ]]; then
        (
            cd "$login_app_dir"
            docker compose up -d --no-build
            docker compose exec -T laravel.test npm run build
            docker compose exec -T laravel.test php artisan optimize:clear
            docker compose exec -T laravel.test php artisan route:list --name=academic
        )
    else
        "$SCRIPT_DIR/prepare-interface-runtime.sh" "$login_app_dir"
    fi

    printf '\nOK: la bandeja gráfica de Notificaciones usa el Login, la sesión y el Compose de %s.\n' "$login_app_dir"
    printf 'Abra /academico/notificaciones; después del login se redirige a esa pantalla.\n'
    exit 0
fi

notifications_app_dir="${NOTIFICATIONS_APP_DIR:-$work_root/$notifications_app_name}"

printf 'MODO: interfaz autónoma de Notificaciones\n'
printf 'APP_DIR: %s\n' "$notifications_app_dir"
printf 'RUTAS RESULTANTES: /academico/login y la interfaz gráfica /academico/notificaciones\n'

if $plan; then
    exit 0
fi

if ! $skip_dependencies; then
    "$SCRIPT_DIR/install-interface-dependencies.sh"
fi

if [[ -e "$notifications_app_dir" ]] && ! is_laravel_app "$notifications_app_dir"; then
    printf 'ERROR: el destino existe, pero no es una aplicación Laravel: %s\n' "$notifications_app_dir" >&2
    exit 1
fi

if ! is_laravel_app "$notifications_app_dir"; then
    notifications_parent="$(dirname -- "$notifications_app_dir")"
    notifications_name="$(basename -- "$notifications_app_dir")"
    mkdir -p "$notifications_parent"

    (
        cd "$notifications_parent"
        laravel new "$notifications_name" \
            --using="$livewire_starter" \
            --phpunit \
            --database=sqlite \
            --npm \
            --no-boost \
            --no-interaction
    )
fi

"$SCRIPT_DIR/install-interface-module.sh" \
    academico-notificaciones \
    "$notifications_app_dir"

"$SCRIPT_DIR/prepare-interface-runtime.sh" "$notifications_app_dir"

printf '\nOK: la bandeja gráfica de Notificaciones quedó disponible como frontend autónomo en %s.\n' "$notifications_app_dir"
printf 'Abra /academico/notificaciones; el sistema solicitará iniciar sesión cuando corresponda.\n'
