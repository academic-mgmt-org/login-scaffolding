#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCAFFOLDING_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly PATCH_DIR="$SCAFFOLDING_DIR/patches"
readonly LOCK_DIR="$SCAFFOLDING_DIR/locks"
readonly PROTOC_IMAGE='debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df'

usage() {
    cat <<'USAGE'
Uso:
  install-interface-module.sh <servicio> [directorio-laravel] [--plan] [--skip-dependencies]

Servicios:
  academico-login
  academico-usuarios
  academico-matriculas
  academico-calificaciones
  academico-solicitudes
  academico-notificaciones

Opciones:
  --plan               Muestra exactamente qué se instalaría sin modificar archivos.
  --skip-dependencies  Omite Composer; pensado para una aplicación ya preparada o CI.

ACADEMIC_REPOS_ROOT puede apuntar a un directorio que contenga clones locales
de los repositorios. Si no se define, los contratos fijados se obtienen con Git.
Una aplicación puede acumular varios módulos; Auth y la sesión se comparten.
USAGE
}

module=''
app_dir='.'
plan=false
skip_dependencies=false
positional=0

while (($# > 0)); do
    case "$1" in
        --plan) plan=true ;;
        --skip-dependencies) skip_dependencies=true ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            printf 'ERROR: opción desconocida: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if ((positional == 0)); then
                module="$1"
            elif ((positional == 1)); then
                app_dir="$1"
            else
                printf 'ERROR: se recibieron demasiados argumentos.\n' >&2
                usage >&2
                exit 2
            fi
            positional=$((positional + 1))
            ;;
    esac
    shift
done

case "$module" in
    login|auth|autenticacion) module='academico-login' ;;
    usuarios) module='academico-usuarios' ;;
    matriculas) module='academico-matriculas' ;;
    calificaciones) module='academico-calificaciones' ;;
    solicitudes) module='academico-solicitudes' ;;
    notificaciones) module='academico-notificaciones' ;;
esac

case "$module" in
    academico-login)
        domain='auth'
        repository='https://github.com/academic-mgmt-org/academico-login.git'
        revision='f3504a54fd85be1d9c72c0eeea3aaa58f04233d6'
        proto_source='proto/auth.proto'
        proto_file='auth_v1.proto'
        proto_hash='977f8c04fe026e2f40c1d90ea626d1784c13ca67a7db3809f6dbebe5418b34c4'
        module_patch='0100-academico-login.patch'
        route_slug='sesiones'
        ;;
    academico-usuarios)
        domain='usuarios'
        repository='https://github.com/academic-mgmt-org/academico-usuarios.git'
        revision='782edab9d6905b93b3addcd364b53034973baf1f'
        proto_source='proto/usuarios/v1/usuarios.proto'
        proto_file='usuarios_v1.proto'
        proto_hash='f8d8389426b61c94d6d8eaeb6cf8e7caecf65f50555bf5032bb0e61aa5304dec'
        module_patch='0200-academico-usuarios.patch'
        route_slug='usuarios'
        ;;
    academico-matriculas)
        domain='matriculas'
        repository='https://github.com/academic-mgmt-org/academico-matriculas.git'
        revision='a1eb14a96a747ec42649275251d4a0c1267edab5'
        proto_source='proto/matriculas/v1/matriculas.proto'
        proto_file='matriculas_v1.proto'
        proto_hash='c55147e1fe042edc957507e76e531fff726b9abd9792520debd9e0adb01ae26e'
        module_patch='0300-academico-matriculas.patch'
        route_slug='matriculas'
        ;;
    academico-calificaciones)
        domain='calificaciones'
        repository='https://github.com/academic-mgmt-org/academico-calificaciones.git'
        revision='bdc6215603dc50ea2266120fa454614929b47fb1'
        proto_source='proto/calificaciones/v1/calificaciones.proto'
        proto_file='calificaciones_v1.proto'
        proto_hash='e49e868b86734d9c0d5ef42fda28c9ac27f9eaa80ce1bec34b9b4c19bdd41fb9'
        module_patch='0400-academico-calificaciones.patch'
        route_slug='calificaciones'
        ;;
    academico-solicitudes)
        domain='solicitudes'
        repository='https://github.com/academic-mgmt-org/academico-solicitudes.git'
        revision='f93079c090480dfb0563cf9e15a03e59ba906a38'
        proto_source='proto/solicitudes/v1/solicitudes.proto'
        proto_file='solicitudes_v1.proto'
        proto_hash='6b17f446126af99d30d82f3a940f11613f710841b11321b9b0c9cff876707f5d'
        module_patch='0500-academico-solicitudes.patch'
        route_slug='solicitudes'
        ;;
    academico-notificaciones)
        domain='notificaciones'
        repository='https://github.com/academic-mgmt-org/academico-notificaciones.git'
        revision='5949a05807246739b2f562a1d64d07764cea9c73'
        proto_source='proto/notificaciones/v1/notificaciones.proto'
        proto_file='notificaciones_v1.proto'
        proto_hash='bd0002f8d9ad3bc0c5f1d918f29bffa8dad198f20317bee6ad3d44238cbbe1c3'
        module_patch='0600-academico-notificaciones.patch'
        route_slug='notificaciones'
        ;;
    *)
        printf 'ERROR: servicio no soportado: %s\n' "${module:-<vacío>}" >&2
        usage >&2
        exit 2
        ;;
esac

readonly AUTH_REPOSITORY='https://github.com/academic-mgmt-org/academico-login.git'
readonly AUTH_REVISION='f3504a54fd85be1d9c72c0eeea3aaa58f04233d6'
readonly AUTH_PROTO_SOURCE='proto/auth.proto'
readonly AUTH_PROTO_HASH='977f8c04fe026e2f40c1d90ea626d1784c13ca67a7db3809f6dbebe5418b34c4'
readonly CORE_PATCH="$PATCH_DIR/0001-interface-core.patch"
readonly PLUGGABLE_PATCH="$PATCH_DIR/0002-pluggable-modules.patch"
readonly SELECTED_PATCH="$PATCH_DIR/$module_patch"
readonly NOTIFICATIONS_UI_PATCH="$PATCH_DIR/0601-academico-notificaciones-ui.patch"

if [[ ! -f "$CORE_PATCH" || ! -f "$PLUGGABLE_PATCH" || ! -f "$SELECTED_PATCH" ]]; then
    printf 'ERROR: faltan los parches para %s en %s.\n' "$module" "$PATCH_DIR" >&2
    exit 1
fi

if [[ "$module" == 'academico-notificaciones' && ! -f "$NOTIFICATIONS_UI_PATCH" ]]; then
    printf 'ERROR: falta la interfaz gráfica de Notificaciones en %s.\n' "$PATCH_DIR" >&2
    exit 1
fi

if $plan; then
    printf 'MÓDULO: %s\n' "$module"
    printf 'APLICACIÓN: %s\n' "$app_dir"
    printf 'STUBS: Starter Kit + php artisan make:*\n'
    printf 'PARCHE COMÚN: %s\n' "$CORE_PATCH"
    printf 'PARCHE PLUGABLE: %s\n' "$PLUGGABLE_PATCH"
    printf 'PARCHE DEL MÓDULO: %s\n' "$SELECTED_PATCH"
    if [[ "$module" == 'academico-notificaciones' ]]; then
        printf 'INTERFAZ DE USUARIO: %s\n' "$NOTIFICATIONS_UI_PATCH"
    fi
    printf 'CONTRATO TÉCNICO: academico-login@%s (%s)\n' "$AUTH_REVISION" "$AUTH_PROTO_SOURCE"
    if [[ "$module" != 'academico-login' ]]; then
        printf 'CONTRATO FUNCIONAL ÚNICO: %s@%s (%s)\n' "$module" "$revision" "$proto_source"
    fi
    printf 'CLIENTES GENERADOS: auth%s\n' "$([[ "$domain" == auth ]] && printf '' || printf ' + %s' "$domain")"
    printf 'RUTA: /academico/%s\n' "$route_slug"
    exit 0
fi

for command_name in composer cp docker git grep head id mktemp php sed sha256sum uname; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'ERROR: falta el comando requerido: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ ! -f "$app_dir/artisan" || ! -f "$app_dir/composer.json" ]]; then
    printf 'ERROR: no se encontró una aplicación Laravel en %s.\n' "$app_dir" >&2
    exit 1
fi

app_dir="$(cd -- "$app_dir" && pwd)"
cd "$app_dir"

legacy_module=''
if [[ -f config/academic-module.php ]]; then
    legacy_module="$(sed -n "s/^[[:space:]]*'key'[[:space:]]*=>[[:space:]]*'\([^']*\)'.*/\1/p" config/academic-module.php | head -n 1)"
fi

module_config="config/academic-modules/$module.php"
module_already_installed=false

if [[ "$legacy_module" == "$module" || -f "$module_config" ]]; then
    module_already_installed=true
fi

if [[ -n "$legacy_module" && "$legacy_module" != "$module" ]]; then
    printf 'HOST DETECTADO: %s; se agregará %s en la misma aplicación.\n' "$legacy_module" "$module"
elif compgen -G 'config/academic-modules/academico-*.php' >/dev/null 2>&1; then
    printf 'HOST MODULAR DETECTADO: se agregará o actualizará %s.\n' "$module"
fi

if ! $skip_dependencies; then
    composer require \
        grpc/grpc:^1.81 \
        google/protobuf:^5.35 \
        'ext-grpc:*' \
        --ignore-platform-req=ext-grpc \
        --no-update \
        --no-interaction

    cp "$LOCK_DIR/composer.lock" composer.lock
    cp "$LOCK_DIR/package-lock.json" package-lock.json
    composer install --ignore-platform-req=ext-grpc --no-interaction
fi

generate_if_missing() {
    local target="$1"
    shift

    if [[ -e "$target" ]]; then
        printf 'STUB EXISTENTE: %s\n' "$target"
        return
    fi

    php artisan "$@" --no-interaction
}

generate_if_missing app/Contracts/AcademicGateway.php make:interface Contracts/AcademicGateway
generate_if_missing app/Services/GrpcAcademicGateway.php make:class Services/GrpcAcademicGateway
generate_if_missing app/Exceptions/AcademicGatewayException.php make:exception AcademicGatewayException
generate_if_missing app/Providers/AcademicInterfaceServiceProvider.php make:provider AcademicInterfaceServiceProvider
generate_if_missing app/Http/Middleware/EnsureAcademicGatewaySession.php make:middleware EnsureAcademicGatewaySession
generate_if_missing app/Http/Controllers/AcademicSessionController.php make:controller AcademicSessionController
generate_if_missing app/Http/Controllers/AcademicInterfaceController.php make:controller AcademicInterfaceController
generate_if_missing config/academic-interface.php make:config academic-interface
generate_if_missing config/academic-module.php make:config academic-module
generate_if_missing resources/views/academic-interface/login.blade.php make:view academic-interface.login
generate_if_missing resources/views/academic-interface/forgot-password.blade.php make:view academic-interface.forgot-password
generate_if_missing resources/views/academic-interface/reset-password.blade.php make:view academic-interface.reset-password
generate_if_missing resources/views/academic-interface/interface.blade.php make:view academic-interface.interface
generate_if_missing resources/views/academic-interface/layout.blade.php make:view academic-interface.layout
generate_if_missing tests/Feature/AcademicInterfaceTest.php make:test AcademicInterfaceTest

for view in \
    resources/views/academic-interface/login.blade.php \
    resources/views/academic-interface/forgot-password.blade.php \
    resources/views/academic-interface/reset-password.blade.php \
    resources/views/academic-interface/interface.blade.php \
    resources/views/academic-interface/layout.blade.php; do
    if grep -q '<!-- .* -->' "$view"; then
        sed -i '/<!-- .* -->/c\    <!-- Normalized Laravel view stub. -->' "$view"
    fi
done

GIT_APPLY=(git apply)
if project_prefix="$(git rev-parse --show-prefix 2>/dev/null)" && [[ -n "$project_prefix" ]]; then
    GIT_APPLY+=(--directory="$project_prefix")
fi

patch_is_installed() {
    local patch_name
    local installed_module

    patch_name="$(basename -- "$1")"

    case "$patch_name" in
        0001-interface-core.patch)
            [[ -f app/Services/GrpcAcademicGateway.php ]] &&
                grep -Fq 'class GrpcAcademicGateway implements AcademicGateway' app/Services/GrpcAcademicGateway.php &&
                grep -Fq "name('academic.login')" routes/web.php
            ;;
        0002-pluggable-modules.patch)
            [[ -f app/Support/AcademicModules.php ]] &&
                grep -Fq 'final class AcademicModules' app/Support/AcademicModules.php &&
                grep -Fq "'{academicModule}'" routes/web.php
            ;;
        0601-academico-notificaciones-ui.patch)
            [[ -f app/Http/Controllers/AcademicNotificationController.php ]] &&
                [[ -f resources/views/academic-interface/notifications.blade.php ]] &&
                [[ -f config/academic-presentations.php ]] &&
                grep -Fq 'notification-inbox' config/academic-presentations.php
            ;;
        [0-9][0-9]00-academico-*.patch)
            installed_module="${patch_name#[0-9][0-9]00-}"
            installed_module="${installed_module%.patch}"
            [[ -f "config/academic-modules/$installed_module.php" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

apply_once() {
    local patch_file="$1"

    if "${GIT_APPLY[@]}" --check "$patch_file" 2>/dev/null; then
        "${GIT_APPLY[@]}" "$patch_file"
        printf 'PARCHE APLICADO: %s\n' "$(basename "$patch_file")"
    elif "${GIT_APPLY[@]}" --reverse --check "$patch_file" 2>/dev/null; then
        printf 'PARCHE YA APLICADO: %s\n' "$(basename "$patch_file")"
    elif patch_is_installed "$patch_file"; then
        printf 'PARCHE YA INTEGRADO: %s\n' "$(basename "$patch_file")"
    else
        printf 'ERROR: %s no corresponde a los stubs generados.\n' "$patch_file" >&2
        printf 'Use la revisión del Starter Kit indicada en docs/.\n' >&2
        exit 1
    fi
}

apply_once "$CORE_PATCH"
apply_once "$PLUGGABLE_PATCH"

if $module_already_installed && [[ ! -f "$module_config" ]]; then
    printf 'MÓDULO LEGACY CONSERVADO: %s\n' "$module"
else
    apply_once "$SELECTED_PATCH"
fi

if [[ "$module" == 'academico-notificaciones' ]]; then
    apply_once "$NOTIFICATIONS_UI_PATCH"
fi

mkdir -p proto
proto_sources="$(mktemp -d)"
cleanup() { rm -rf "$proto_sources"; }
trap cleanup EXIT

copy_contract() {
    local repo_name="$1"
    local repo_url="$2"
    local repo_revision="$3"
    local source_path="$4"
    local destination="$5"
    local expected_hash="$6"
    local local_source="${ACADEMIC_REPOS_ROOT:-}/$repo_name/$source_path"

    if [[ -n "${ACADEMIC_REPOS_ROOT:-}" && -f "$local_source" ]]; then
        cp "$local_source" "$destination"
        printf 'CONTRATO LOCAL: %s\n' "$local_source"
    else
        local checkout="$proto_sources/$repo_name"
        git init -q "$checkout"
        git -C "$checkout" remote add origin "$repo_url"
        git -C "$checkout" fetch -q --depth=1 origin "$repo_revision"
        git -C "$checkout" show "FETCH_HEAD:$source_path" > "$destination"
        printf 'CONTRATO FIJADO: %s@%s\n' "$repo_name" "$repo_revision"
    fi

    printf '%s  %s\n' "$expected_hash" "$destination" | sha256sum --check --strict -
}

copy_contract \
    academico-login \
    "$AUTH_REPOSITORY" \
    "$AUTH_REVISION" \
    "$AUTH_PROTO_SOURCE" \
    proto/auth_v1.proto \
    "$AUTH_PROTO_HASH"

proto_arguments=(proto/auth_v1.proto)
if [[ "$module" != 'academico-login' ]]; then
    copy_contract \
        "$module" \
        "$repository" \
        "$revision" \
        "$proto_source" \
        "proto/$proto_file" \
        "$proto_hash"
    proto_arguments+=("proto/$proto_file")
fi

add_php_options() {
    local proto="$1"
    local proto_domain="$2"

    case "$proto_domain" in
        auth)
            sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\AuthV1";' "$proto"
            sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Auth\\\\V1";' "$proto"
            ;;
        usuarios)
            sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\UsuariosV1";' "$proto"
            sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Usuarios\\\\V1";' "$proto"
            ;;
        matriculas)
            sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\MatriculasV1";' "$proto"
            sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Matriculas\\\\V1";' "$proto"
            ;;
        calificaciones)
            sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\CalificacionesV1";' "$proto"
            sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Calificaciones\\\\V1";' "$proto"
            ;;
        solicitudes)
            sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\SolicitudesV1";' "$proto"
            sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Solicitudes\\\\V1";' "$proto"
            ;;
        notificaciones)
            sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\NotificacionesV1";' "$proto"
            sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Notificaciones\\\\V1";' "$proto"
            ;;
    esac
}

add_php_options proto/auth_v1.proto auth
if [[ "$module" != 'academico-login' ]]; then
    add_php_options "proto/$proto_file" "$domain"
fi

workspace_path="$PWD"
case "$(uname -s)" in
    MINGW*|MSYS*) workspace_path="$(pwd -W)" ;;
esac

printf -v protoc_files ' %q' "${proto_arguments[@]}"
MSYS_NO_PATHCONV=1 docker run --rm \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -e PROTO_FILES="${protoc_files# }" \
    -v "$workspace_path:/workspace" \
    -w /workspace \
    "$PROTOC_IMAGE" \
    sh -lc '
        apt-get update >/dev/null &&
        apt-get install -y --no-install-recommends \
            protobuf-compiler=3.21.12-3+deb12u1 \
            protobuf-compiler-grpc=1.51.1-3+b1 >/dev/null &&
        rm -rf /tmp/generated && mkdir -p /tmp/generated app/Grpc &&
        eval "set -- $PROTO_FILES" &&
        protoc --proto_path=proto \
            --php_out=/tmp/generated \
            --grpc_out=/tmp/generated \
            --plugin=protoc-gen-grpc=/usr/bin/grpc_php_plugin \
            "$@" &&
        cp -R /tmp/generated/App/Grpc/. app/Grpc/ &&
        chown -R "$HOST_UID:$HOST_GID" app/Grpc
    '

composer dump-autoload --ignore-platform-req=ext-grpc --no-interaction
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan route:list --name=academic
php artisan test --filter=AcademicInterfaceTest

cleanup
trap - EXIT

printf '\nOK: %s quedó instalado como módulo plugable.\n' "$module"
printf 'Abra /academico/login y, después de autenticarse, /academico/%s.\n' "$route_slug"
