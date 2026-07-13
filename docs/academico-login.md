# Interfaz independiente: academico-login

Esta receta instala únicamente autenticación y sesiones: login, emisión y
validación de JWT, refresh, logout, recuperación de contraseña, reglas de
acceso y comprobaciones de salud. No compila ni registra clientes de Usuarios,
Matrículas, Calificaciones, Solicitudes o Notificaciones.

## Crear e instalar

Ejecutar el bloque completo desde la raíz de este repositorio. El nombre del
directorio puede cambiarse mediante `APP_NAME`; `WORK_ROOT` permite elegir otra
ruta relativa para las aplicaciones generadas.

```bash
# ===== INICIO: INTERFAZ SOLO PARA ACADEMICO-LOGIN =====
set -Eeuo pipefail

WORK_ROOT="${WORK_ROOT:-../interfaces-academicas}"
APP_NAME="${APP_NAME:-interfaz-academico-login}"
APP_DIR="$WORK_ROOT/$APP_NAME"
LIVEWIRE_STARTER='laravel/livewire-starter-kit:dev-main#1f84e33e6bf6c95f9925e3e023bce71341ced005'

./setup/install-interface-dependencies.sh

mkdir -p "$WORK_ROOT"
(cd "$WORK_ROOT" && laravel new "$APP_NAME" \
    --using="$LIVEWIRE_STARTER" \
    --phpunit \
    --database=sqlite \
    --npm \
    --no-boost \
    --no-interaction)

./setup/install-interface-module.sh \
  academico-login \
  "$APP_DIR"

./setup/prepare-interface-runtime.sh \
  "$APP_DIR"
# ===== FIN: INTERFAZ SOLO PARA ACADEMICO-LOGIN =====
```

El runtime también se genera: Sail crea `compose.yaml` y el preparador construye
la capa PHP 8.5 con la extensión gRPC antes de ejecutar migraciones y Vite.

El resultado contiene solo `proto/auth_v1.proto`, las clases
`App\Grpc\Auth\V1` y metadatos Auth. La pantalla de acceso está en
`/academico/login` y la interfaz de sesión en `/academico/sesiones`.

## Ejecutar y comprobar

```bash
cd "${WORK_ROOT:-../interfaces-academicas}/${APP_NAME:-interfaz-academico-login}"
docker compose up -d --no-build
docker compose exec -T laravel.test php artisan route:list --name=academic
```

El host predeterminado es
`academia-dev.eastus2.cloudapp.azure.com:50050`. Puede cambiarse en `.env` con
`GATEWAY_GRPC_HOST`; para un endpoint TLS, definir además
`GATEWAY_GRPC_TLS=true`.
