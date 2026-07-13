# Interfaz independiente: academico-notificaciones

Esta receta instala únicamente Notificaciones: creación, bandeja, recientes,
contador de no leídas, lectura individual, lectura masiva y envío de correo.
Auth se compila solo como dependencia técnica para obtener la identidad y la
sesión; no se instalan Usuarios, Matrículas, Calificaciones ni Solicitudes.

## Crear e instalar

Ejecutar el bloque completo desde la raíz de este repositorio. La ruta `.` de
`SCAFFOLDING_DIR` referencia esa raíz sin depender de su ubicación absoluta.

```bash
# ===== INICIO: INTERFAZ SOLO PARA ACADEMICO-NOTIFICACIONES =====
set -Eeuo pipefail

SCAFFOLDING_DIR='.'
WORK_ROOT="${WORK_ROOT:-$HOME/interfaces-academicas}"
APP_NAME="${APP_NAME:-interfaz-academico-notificaciones}"
LIVEWIRE_STARTER='laravel/livewire-starter-kit:dev-main#1f84e33e6bf6c95f9925e3e023bce71341ced005'

"$SCAFFOLDING_DIR/setup/install-interface-dependencies.sh"

mkdir -p "$WORK_ROOT"
(cd "$WORK_ROOT" && laravel new "$APP_NAME" \
    --using="$LIVEWIRE_STARTER" \
    --phpunit \
    --database=sqlite \
    --npm \
    --no-boost \
    --no-interaction)

"$SCAFFOLDING_DIR/setup/install-interface-module.sh" \
  academico-notificaciones \
  "$WORK_ROOT/$APP_NAME"

"$SCAFFOLDING_DIR/setup/prepare-interface-runtime.sh" \
  "$WORK_ROOT/$APP_NAME"
# ===== FIN: INTERFAZ SOLO PARA ACADEMICO-NOTIFICACIONES =====
```

El runtime también se genera: Sail crea `compose.yaml` y el preparador construye
la capa PHP 8.5 con la extensión gRPC antes de ejecutar migraciones y Vite.

El resultado compila exactamente `auth_v1.proto` y
`notificaciones_v1.proto`. La pantalla de acceso está en `/academico/login` y
el flujo funcional queda en `/academico/notificaciones`. No es necesario
ejecutar ninguna receta de los otros servicios.

## Ejecutar y comprobar

```bash
cd "${WORK_ROOT:-$HOME/interfaces-academicas}/${APP_NAME:-interfaz-academico-notificaciones}"
find proto -maxdepth 1 -type f -printf '%f\n' | sort
docker compose up -d --no-build
docker compose exec -T laravel.test php artisan route:list --name=academic
```

El host predeterminado puede sustituirse con `GATEWAY_GRPC_HOST` en `.env`; si
el gateway usa TLS, definir `GATEWAY_GRPC_TLS=true`.
