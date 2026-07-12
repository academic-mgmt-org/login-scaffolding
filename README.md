# Login Scaffolding

Ejemplo reproducible de autenticación Laravel contra un gateway gRPC. La
interfaz proviene del Starter Kit oficial de Livewire; el objetivo de este
repositorio es demostrar el flujo funcional, no proponer un diseño visual.

El proyecto ejecuta, en este orden:

1. `auth.v1.AuthService/Login`.
2. `notificaciones.v1.NotificationService/CountUnread`.
3. `ListNotifications` para las no leídas y `RecentNotifications` para las
   recientes, siempre con `authorization: Bearer <JWT>`.
4. `auth.v1.AuthService/Logout` con access token y refresh token.
5. Las pruebas negativas sin login y con el token revocado.

El gateway configurado por defecto es:

```text
academia-dev.eastus2.cloudapp.azure.com:50050
```

## Crear el login desde cero con plantillas predefinidas

Esta es la ruta principal solicitada. Comienza en un directorio que todavía no
contiene un proyecto Laravel y utiliza el Starter Kit oficial de Livewire. No
se crean vistas, controladores, middleware ni pruebas con archivos vacíos.

### 1. Verificar requisitos

Laravel 13 requiere PHP 8.3 o superior. El Starter Kit actual también necesita
Composer y Node 20.19 o superior.

```bash
php --version
composer --version
node --version
npm --version
docker --version
docker compose version
grpcurl --version
```

Si PHP, Composer y el instalador de Laravel no están disponibles en Linux, el
instalador oficial se obtiene con:

```bash
/bin/bash -c "$(curl -fsSL https://php.new/install/linux/8.5)"
exec "$SHELL" -l
composer global require laravel/installer
```

### 2. Crear el proyecto con el Starter Kit oficial

```bash
laravel new sistema-login \
  --livewire \
  --phpunit \
  --database=sqlite \
  --npm \
  --no-boost \
  --no-interaction

cd sistema-login
```

Ese único scaffold crea el formulario de login, Fortify, las rutas `/login` y
`/logout`, validaciones, rate limiting, sesiones, middleware, estilos, Vite,
migraciones y pruebas base. En Laravel 13 la plantilla PHP/Blade oficial es
Livewire; Breeze corresponde a generaciones anteriores de Laravel.

Para comprobar el login local recién generado antes de conectarlo al gateway:

```bash
php artisan migrate
npm run build
composer run dev
```

En otra terminal:

```bash
curl -I http://127.0.0.1:8000/login
```

Detener `composer run dev` con `Ctrl+C` antes de continuar.

### 3. Generar desde plantillas las extensiones del gateway

```bash
composer require \
  grpc/grpc:^1.81 \
  google/protobuf:^5.35 \
  ext-grpc:* \
  --ignore-platform-req=ext-grpc \
  --no-interaction

php artisan make:interface Contracts/GatewayClient --no-interaction
php artisan make:class Services/GrpcGatewayClient --no-interaction
php artisan make:exception GatewayRpcException --no-interaction
php artisan make:controller NotificationController --invokable --no-interaction
php artisan make:middleware RevokeGatewaySessionOnLogout --no-interaction
php artisan make:command GatewaySmokeCommand --no-interaction
php artisan make:config gateway --no-interaction
php artisan make:view notifications.index --no-interaction
php artisan make:test GatewayAuthenticationTest --no-interaction
```

Todos esos archivos nacen de stubs mantenidos por Laravel. La implementación de
este repositorio completa los stubs para delegar el login de Fortify al gateway,
guardar los tokens en la sesión del servidor, consultar notificaciones y
revocar la sesión en logout.

### 4. Generar contratos y clientes gRPC

Los `.proto` tampoco se redactan a mano: se exportan desde la reflexión del
gateway y luego `protoc` genera las clases PHP.

```bash
mkdir -p proto

grpcurl -plaintext \
  -proto-out-dir proto \
  academia-dev.eastus2.cloudapp.azure.com:50050 \
  describe auth.v1.AuthService

grpcurl -plaintext \
  -proto-out-dir proto \
  academia-dev.eastus2.cloudapp.azure.com:50050 \
  describe notificaciones.v1.NotificationService

sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\AuthV1";' proto/auth_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Auth\\\\V1";' proto/auth_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\NotificacionesV1";' proto/notificaciones_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Notificaciones\\\\V1";' proto/notificaciones_v1.proto

docker run --rm \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -v "$PWD:/workspace" \
  -w /workspace \
  debian:bookworm-slim \
  sh -lc '
    apt-get update >/dev/null &&
    apt-get install -y --no-install-recommends \
      protobuf-compiler protobuf-compiler-grpc >/dev/null &&
    mkdir -p /tmp/generated &&
    protoc --proto_path=proto \
      --php_out=/tmp/generated \
      --grpc_out=/tmp/generated \
      --plugin=protoc-gen-grpc=/usr/bin/grpc_php_plugin \
      proto/auth_v1.proto proto/notificaciones_v1.proto &&
    cp -R /tmp/generated/App/Grpc app/ &&
    chown -R "$HOST_UID:$HOST_GID" app/Grpc
  '

composer dump-autoload
```

### 5. Generar el entorno Docker desde Laravel Sail

```bash
php artisan sail:install --with=none --no-interaction
php artisan sail:publish --no-interaction

docker compose build --build-arg PHP_EXTENSIONS=grpc
docker compose up -d
```

La aplicación queda disponible en `http://localhost/login`. Si se configura
`APP_PORT=8000`, queda en `http://localhost:8000/login`.

### 6. Validar el resultado

```bash
docker compose exec laravel.test php artisan migrate --force
docker compose exec laravel.test npm run build
docker compose exec laravel.test php artisan test
docker compose exec laravel.test php artisan gateway:smoke
```

El último comando solicita usuario y contraseña de forma interactiva y ejecuta
login, consultas protegidas, logout, validación del token revocado y las dos
pruebas negativas.

### 7. Crear otro proyecto desde esta plantilla terminada

Este repositorio también está marcado como plantilla de GitHub. Los miembros de
`academic-mgmt-org` pueden crear otra aplicación funcional, sin volver a editar
los stubs, con un único comando:

```bash
gh repo create academic-mgmt-org/mi-login \
  --template academic-mgmt-org/login-scaffolding \
  --private \
  --clone

cd mi-login
cp .env.example .env
docker compose build
docker compose run --rm laravel.test composer install --no-interaction
docker compose run --rm laravel.test php artisan key:generate
docker compose run --rm laravel.test php artisan migrate --force
docker compose run --rm laravel.test npm ci
docker compose run --rm laravel.test npm run build
docker compose up -d
```

La sección anterior explica cómo construir la propia plantilla desde cero con
`laravel new --livewire`; esta alternativa instancia directamente el resultado
ya integrado con el gateway.

## Regla de construcción: solo scaffolding y plantillas

Ningún archivo estructural de la aplicación se creó con `touch`, heredocs ni
copias escritas a mano. Cada pieza parte de una plantilla o un generador:

| Pieza | Generador o plantilla |
| --- | --- |
| Aplicación, login, rutas, Fortify, Livewire y estilos | `laravel new --livewire` |
| Cliente, contrato, excepción, controlador, middleware, comando, vista, configuración y prueba | `php artisan make:*` |
| Contratos `.proto` | reflexión del gateway con `grpcurl -proto-out-dir` |
| Clases y clientes PHP gRPC | `protoc` + `grpc_php_plugin` |
| Contenedor y Compose | `php artisan sail:install` y `sail:publish` |
| `README.md` inicial | plantilla `--add-readme` de GitHub CLI |

Los archivos generados se adaptaron para conectar esas plantillas con el flujo
del gateway. Los archivos bajo `app/Grpc` incluyen la cabecera `GENERATED CODE
-- DO NOT EDIT` y se regeneran desde los `.proto`.

## Puesta en marcha desde comandos

Solo se necesitan Git, Docker y Docker Compose. PHP, Composer, Node y la
extensión gRPC se ejecutan dentro de Laravel Sail.

```bash
git clone https://github.com/academic-mgmt-org/login-scaffolding.git
cd login-scaffolding

cp .env.example .env
docker compose build
docker compose run --rm laravel.test composer install --no-interaction
docker compose run --rm laravel.test php artisan key:generate
docker compose run --rm laravel.test php artisan migrate --force
docker compose run --rm laravel.test npm install
docker compose run --rm laravel.test npm run build
docker compose up -d
```

Abrir:

```text
http://localhost:8000/login
```

Para detenerlo:

```bash
docker compose down
```

## Credenciales

No hay credenciales reales confirmadas en Git. La pantalla solicita el usuario
y la contraseña y los envía directamente al RPC `Login`. El campo se llama
`email` porque así lo genera Fortify, pero su valor se utiliza como `username`
del gateway.

Para el smoke test se recomienda la entrada interactiva, que no deja la
contraseña en el historial de la terminal:

```bash
docker compose exec laravel.test php artisan gateway:smoke
```

También puede indicarse solo el usuario:

```bash
docker compose exec laravel.test \
  php artisan gateway:smoke --username=usuario@institucion.edu.ec
```

Para automatización, definir `GATEWAY_SMOKE_USERNAME` y
`GATEWAY_SMOKE_PASSWORD` únicamente en el entorno o en un archivo `.env` no
versionado; después ejecutar:

```bash
docker compose exec laravel.test php artisan gateway:smoke --no-prompt
```

El comando no imprime tokens. Si el flujo falla después del login, intenta
cerrar la sesión remota en un bloque de limpieza.

## Qué ocurre al iniciar y cerrar sesión

### Login

El formulario generado por Livewire envía `POST /login`. Fortify conserva su
validación y rate limiting, pero `Fortify::authenticateUsing` delega las
credenciales a `GatewayClient::login`.

Si el gateway responde correctamente:

- Laravel crea o actualiza un usuario sombra local para que el guard de sesión
  pueda identificar la petición. La contraseña local es aleatoria y nunca se
  usa para autenticar.
- `accessToken`, `refreshToken` y `sessionId` se guardan solo en la sesión del
  servidor.
- Los tokens no se escriben en HTML, JavaScript, `localStorage` ni logs.

### Notificaciones

`GET /dashboard` exige el middleware `auth`. El controlador obtiene el access
token de la sesión y llama al mismo host gRPC:

```text
CountUnread -> ListNotifications(estado=no_leido, limit=unreadCount)
            -> RecentNotifications(limit=5)
```

El cliente envía `authorization: Bearer <JWT>` y no envía `x-api-key`; esa clave
la agrega el gateway al reenviar la petición.

### Logout

El `POST /logout` generado por Fortify pasa primero por
`RevokeGatewaySessionOnLogout`. Ese middleware llama a `AuthService/Logout`
con ambos tokens y luego Fortify elimina la sesión local, incluso si el gateway
no está disponible.

## Pruebas

Pruebas aisladas, sin usar credenciales ni la red:

```bash
docker compose exec laravel.test php artisan test
```

Comprobación real de extremo a extremo contra el gateway:

```bash
docker compose exec laravel.test php artisan gateway:smoke
```

El smoke test valida explícitamente:

- rechazo de notificaciones sin `authorization`;
- login y presencia de ambos tokens;
- contador, listado de no leídas y recientes;
- logout remoto;
- `ValidateToken` con `isValid: false`;
- rechazo del access token revocado por notificaciones.

## Auditoría detallada de los generadores

Esta sección permite auditar el scaffolding desde un directorio vacío. El
comando oficial actual de Laravel 13 instala PHP 8.3 o superior y ofrece el
Starter Kit de Livewire durante `laravel new`.

### 1. Starter Kit

```bash
composer global require laravel/installer

laravel new login-scaffolding \
  --livewire \
  --phpunit \
  --database=sqlite \
  --no-boost \
  --no-interaction

cd login-scaffolding
```

Laravel 13 ya no utiliza Breeze como Starter Kit principal. Livewire genera el
login Blade, Fortify, rutas, validaciones, rate limiting, middleware, estilos,
migraciones y pruebas base. En este proyecto se deshabilitaron registro,
recuperación, passkeys y 2FA locales porque el gateway externo es la fuente de
autenticación.

### 2. Dependencias y clases desde plantillas

```bash
composer require grpc/grpc:^1.81 google/protobuf:^5.35 ext-grpc:*

php artisan make:interface Contracts/GatewayClient
php artisan make:class Services/GrpcGatewayClient
php artisan make:exception GatewayRpcException
php artisan make:controller NotificationController --invokable
php artisan make:middleware RevokeGatewaySessionOnLogout
php artisan make:command GatewaySmokeCommand
php artisan make:config gateway
php artisan make:view notifications.index
php artisan make:test GatewayAuthenticationTest
```

### 3. Obtener los contratos desde reflexión

Requiere `grpcurl`. Estos comandos no escriben contratos a mano: los exportan
desde el gateway desplegado.

```bash
mkdir -p proto

grpcurl -plaintext \
  -proto-out-dir proto \
  academia-dev.eastus2.cloudapp.azure.com:50050 \
  describe auth.v1.AuthService

grpcurl -plaintext \
  -proto-out-dir proto \
  academia-dev.eastus2.cloudapp.azure.com:50050 \
  describe notificaciones.v1.NotificationService
```

`grpcurl` exporta `auth_v1.proto` y `notificaciones_v1.proto`. Antes de ejecutar
`protoc`, se agregan por comando los namespaces PHP para que las clases queden
dentro del autoload `App\\` de la plantilla Laravel:

```bash
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\AuthV1";' proto/auth_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Auth\\\\V1";' proto/auth_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\NotificacionesV1";' proto/notificaciones_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Notificaciones\\\\V1";' proto/notificaciones_v1.proto
```

### 4. Generar los clientes PHP

Este comando usa una imagen desechable para instalar las herramientas oficiales
de Protocol Buffers y el plugin PHP de gRPC. El resultado se copia a `app/Grpc`.

```bash
docker run --rm \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -v "$PWD:/workspace" \
  -w /workspace \
  debian:bookworm-slim \
  sh -lc '
    apt-get update >/dev/null &&
    apt-get install -y --no-install-recommends \
      protobuf-compiler protobuf-compiler-grpc >/dev/null &&
    mkdir -p /tmp/generated &&
    protoc --proto_path=proto \
      --php_out=/tmp/generated \
      --grpc_out=/tmp/generated \
      --plugin=protoc-gen-grpc=/usr/bin/grpc_php_plugin \
      proto/auth_v1.proto proto/notificaciones_v1.proto &&
    cp -R /tmp/generated/App/Grpc app/ &&
    chown -R "$HOST_UID:$HOST_GID" app/Grpc
  '

composer dump-autoload
```

### 5. Generar Laravel Sail

```bash
php artisan sail:install --with=none --no-interaction
php artisan sail:publish --no-interaction
```

La plantilla publicada ya admite el argumento `PHP_EXTENSIONS`; en
`compose.yaml` se configuró `PHP_EXTENSIONS: grpc`, que instala `php8.5-grpc` al
construir la imagen.

### 6. Crear y publicar el repositorio

```bash
gh repo create academic-mgmt-org/login-scaffolding \
  --private \
  --add-readme \
  --description "Scaffolding de login Laravel integrado con un gateway gRPC"

git add .
git commit -m "feat: add template-generated Laravel gRPC login flow"
git push -u origin main
```

## Configuración

| Variable | Valor predeterminado | Uso |
| --- | --- | --- |
| `GATEWAY_GRPC_HOST` | `academia-dev.eastus2.cloudapp.azure.com:50050` | Host gRPC h2c |
| `GATEWAY_GRPC_TIMEOUT_MS` | `10000` | Timeout por RPC |
| `GATEWAY_MAX_NOTIFICATIONS` | `500` | Tope defensivo para el listado no leído |
| `GATEWAY_SMOKE_USERNAME` | vacío | Usuario opcional del smoke test |
| `GATEWAY_SMOKE_PASSWORD` | vacío | Contraseña opcional, nunca versionar |

## Decisiones de seguridad

- El gateway de desarrollo usa HTTP/2 h2c; por eso el cliente usa
  `ChannelCredentials::createInsecure()`. Para un ambiente con TLS debe
  cambiarse a credenciales SSL.
- La sesión Laravel está cifrada (`SESSION_ENCRYPT=true`) y se persiste en
  SQLite del lado servidor.
- No se confirma ninguna contraseña, token o API key.
- El navegador nunca llama directamente a los microservicios internos.
- El logout remoto se intenta antes de invalidar la sesión local.
- El rate limiter generado por Fortify conserva cinco intentos por minuto para
  cada combinación de usuario e IP.

## Referencias oficiales

- [Instalación de Laravel 13](https://laravel.com/docs/13.x/installation)
- [Starter Kits oficiales de Laravel](https://laravel.com/starter-kits)
- [Quickstart de gRPC para PHP](https://grpc.io/docs/languages/php/quickstart/)
- [Tutorial básico de gRPC para PHP](https://grpc.io/docs/languages/php/basics/)
