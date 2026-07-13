#!/usr/bin/env bash

set -Eeuo pipefail

readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly INSTALLER="$ROOT/setup/install-interface-module.sh"
readonly RUNTIME="$ROOT/setup/prepare-interface-runtime.sh"
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
bash -n "$RUNTIME"

if ! grep -Fq \
    'generate_if_missing app/Contracts/AcademicGateway.php make:interface Contracts/AcademicGateway' \
    "$INSTALLER"; then
    printf 'ERROR: el stub de AcademicGateway debe generarse dentro de app/Contracts.\n' >&2
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
    grep -Fq "PARCHE ÚNICO DEL MÓDULO: $ROOT/patches/${PATCHES[$module]}" <<<"$output"
    grep -Fq 'CONTRATO TÉCNICO: academico-login@' <<<"$output"
    grep -Fq "CLIENTES GENERADOS: auth$([[ "${DOMAINS[$module]}" == auth ]] && printf '' || printf ' + %s' "${DOMAINS[$module]}")" <<<"$output"

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

    if [[ "$changed_files" != 'config/academic-module.php' ]]; then
        printf 'ERROR: %s modifica archivos fuera de config/academic-module.php.\n' "$module_patch" >&2
        exit 1
    fi

    test -f "$ROOT/docs/$module.md"
    grep -Fq "  $module " "$ROOT/docs/$module.md"
done

printf 'OK: los seis selectores están aislados y documentados.\n'
