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

El gateway configurado por defecto se muestra a continuación. Este bloque es
solo informativo; **no se copia ni se ejecuta**:

```text
academia-dev.eastus2.cloudapp.azure.com:50050
```

## Cómo copiar y ejecutar los comandos

Todos los bloques ejecutables están delimitados por comentarios `INICIO` y
`FIN`. Salvo que el texto indique lo contrario, seleccionar desde el comentario
`INICIO` hasta el comentario `FIN`, incluir ambos y pegar todo de una vez en la
terminal. Los comentarios comienzan con `#`, por lo que Bash los ignora.

- Una línea terminada en `\` continúa en la siguiente: forma parte del mismo
  comando y no debe separarse.
- Cuando un bloque diga `ELEGIR SOLO`, ejecutar únicamente el que corresponda
  y omitir las demás alternativas.
- Cuando se indiquen `TERMINAL 1` y `TERMINAL 2`, mantener la primera abierta y
  ejecutar el segundo bloque en otra ventana o pestaña.
- Esperar siempre a que el bloque termine y vuelva a aparecer el prompt antes
  de continuar, excepto cuando se indique que el proceso queda ejecutándose.

## Crear el login desde cero con plantillas predefinidas

Esta es la ruta principal solicitada. Comienza en un directorio que todavía no
contiene un proyecto Laravel y utiliza el Starter Kit oficial de Livewire. No
se crean vistas, controladores, middleware ni pruebas con archivos vacíos.

> **INICIO DE LA RUTA PRINCIPAL:** seguir las secciones 1 a 8 en orden. En la
> sección 6 se documenta primero la ruta recomendada. La construcción completa
> local es opcional y sustituye a esa ruta; no hay que ejecutar ambas.

### 1. Verificar requisitos

Laravel 13 requiere PHP 8.3 o superior. El Starter Kit actual también necesita
Composer y Node 20.19 o superior. Para el flujo completo se utilizan Docker
Engine con los plugins de Compose y Buildx, `grpcurl` y `fuser`, incluido en el
paquete `psmisc`.

La ruta recomendada reutiliza una imagen de Laravel Sail ya construida y solo
añade el paquete binario `php8.5-grpc` en una capa pequeña. Como alternativa se
conserva la construcción completa con el Dockerfile generado por Sail.
`protoc` y `grpc_php_plugin` se ejecutan en una imagen desechable, por lo que
ninguno de esos tres componentes necesita instalarse en el equipo anfitrión.

Si todavía no está instalada ninguna de las herramientas del proyecto, no hay
que ejecutar instalaciones manuales por separado. Ejecutar el preparador de
dependencias del repositorio:

```bash
# ===== INICIO: PREPARAR TODAS LAS DEPENDENCIAS DEL ANFITRIÓN =====
./setup/install-login-test-dependencies.sh
# ===== FIN DEL BLOQUE DE PREPARACIÓN =====
```

El script instala las herramientas que administra cuando faltan y valida los
requisitos base del sistema. Puede solicitar privilegios con `sudo` para
instalar Buildx.

Con las dependencias preparadas, comprobar el entorno completo:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
php --version
composer --version
node --version
npm --version
docker --version
docker compose version
docker buildx version
grpcurl --version
fuser --version
# ===== FIN DEL BLOQUE =====
```

`docker buildx version` debe imprimir la versión del plugin. Si Docker responde
`unknown command: docker buildx`, Buildx todavía no está instalado correctamente.

### 2. Crear el proyecto con el Starter Kit oficial

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
laravel new sistema-login \
  --livewire \
  --phpunit \
  --database=sqlite \
  --npm \
  --no-boost \
  --no-interaction

cd sistema-login
# ===== FIN DEL BLOQUE =====
```

Ese único scaffold crea el formulario de login, Fortify, las rutas `/login` y
`/logout`, validaciones, rate limiting, sesiones, middleware, estilos, Vite,
migraciones y pruebas base. En Laravel 13 la plantilla PHP/Blade oficial es
Livewire; Breeze corresponde a generaciones anteriores de Laravel.

Para comprobar el login local recién generado antes de conectarlo al gateway:

```bash
# ===== INICIO: TERMINAL 1, COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
php artisan migrate
npm run build
fuser -k -TERM 8000/tcp 2>/dev/null || true
composer run dev
# ===== FIN: DEJAR ESTA TERMINAL EJECUTANDO composer run dev =====
```

El comando `fuser` termina cualquier proceso que esté usando el puerto TCP
8000. `|| true` permite continuar normalmente cuando el puerto ya está libre.

Sin cerrar la terminal anterior, abrir la **TERMINAL 2** y ejecutar todo este
bloque:

```bash
# ===== INICIO: TERMINAL 2, COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
curl -I http://localhost:8000/login
# ===== FIN DEL BLOQUE DE LA TERMINAL 2 =====
```

Detener `composer run dev` con `Ctrl+C` antes de continuar.

### 3. Generar desde plantillas las extensiones del gateway

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
composer require \
  grpc/grpc:^1.81 \
  google/protobuf:^5.35 \
  'ext-grpc:*' \
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

# make:view inserta una cita aleatoria; normalizarla para que el parche sea reproducible.
sed -i '/<!-- .* -->/c\    <!-- Normalized Laravel view stub. -->' \
  resources/views/notifications/index.blade.php
# ===== FIN DEL BLOQUE =====
```

Todos esos archivos nacen de stubs mantenidos por Laravel. La implementación de
este repositorio completa los stubs para delegar el login de Fortify al gateway,
guardar los tokens en la sesión del servidor, consultar notificaciones y
revocar la sesión en logout.

La omisión de `ext-grpc` solo permite completar el scaffolding con el PHP del
anfitrión. La imagen se valida más adelante y no ejecuta la aplicación si la
extensión no quedó cargada.

### 4. Generar contratos y clientes gRPC

Los `.proto` tampoco se redactan a mano: se exportan desde la reflexión del
gateway y luego `protoc` genera las clases PHP.

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
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

composer dump-autoload --ignore-platform-req=ext-grpc
# ===== FIN DEL BLOQUE =====
```

### 5. Aplicar automáticamente la implementación funcional

Los generadores anteriores crean la estructura y los parches de este directorio
incorporan la lógica funcional ya verificada. No hay que abrir ni editar ningún
archivo. El bucle también es seguro al volver a ejecutarlo: omite cada parche
que ya esté aplicado y comprueba los demás antes de modificar el proyecto.

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
(
  set -euo pipefail

  PATCH_DIR="${PATCH_DIR:-../patches}"
  PATCHES=(
    "$PATCH_DIR/0001-gateway-client.patch"
    "$PATCH_DIR/0002-fortify-login-flow.patch"
    "$PATCH_DIR/0003-tests-and-analysis.patch"
  )

  for PATCH_FILE in "${PATCHES[@]}"; do
    if git apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
      echo "Ya aplicado: $(basename "$PATCH_FILE")"
    else
      git apply --check "$PATCH_FILE"
      git apply "$PATCH_FILE"
      echo "Aplicado: $(basename "$PATCH_FILE")"
    fi
  done

  if ! grep -q '^GATEWAY_GRPC_HOST=' .env; then
    cp .env.example .env
    php artisan key:generate --force
  fi

  composer dump-autoload --ignore-platform-req=ext-grpc
  php artisan optimize:clear
)
# ===== FIN DEL BLOQUE =====
```

Los parches se separan por responsabilidad: cliente gRPC, integración con
Fortify y pruebas/análisis estático. No incluyen `.env`, credenciales, tokens,
los `.proto` ni las clases generadas de `app/Grpc`.

### 6. Preparar la imagen de PHP con gRPC

La ruta recomendada se documenta primero y evita reconstruir localmente todo
el entorno de Sail. Parte de `ariaieboy/sail-runtime-image:8.5-24`, fijada por
digest. Esta imagen comunitaria mantiene la interfaz de Sail y contiene PHP
8.5 y Node 24; sobre ella solo se construye una capa pequeña que instala el
paquete binario `php8.5-grpc`. Su
[Dockerfile es público](https://github.com/ariaieboy/sail-runtime-image) y la
[imagen se distribuye en Docker Hub](https://hub.docker.com/r/ariaieboy/sail-runtime-image).

La construcción completa de la imagen con el Dockerfile de Sail es opcional y
se presenta al final de esta sección. Es una alternativa a la ruta recomendada,
no un paso adicional: ejecutar **solo una** de las dos rutas.

#### Ruta recomendada: reutilizar la base preconstruida

Sail 1.63 intenta construir la imagen completa automáticamente durante
`sail:install`. Para evitarlo, `DOCKER_HOST` apunta solo durante ese comando a
un socket no válido; esto no modifica la configuración permanente de Docker.
Después, el `Dockerfile` mínimo se entrega a Docker por la entrada estándar y
no queda como archivo del proyecto. La etiqueta final coincide con la que Sail
genera en `compose.yaml`, por lo que `sail up` utiliza la imagen preparada sin
construir localmente todas las dependencias del entorno.

```bash
# ===== INICIO: RUTA RECOMENDADA, COPIAR Y EJECUTAR TODO =====
DOCKER_HOST=unix:///dev/null \
  php artisan sail:install --with=none --no-interaction

grep -q 'WEBSERVER: cli' compose.yaml || \
  sed -i "/WWWUSER:/i\\            WWWGROUP: '\${WWWGROUP}'\\n            WEBSERVER: cli" compose.yaml

SAIL_BASE_IMAGE='ariaieboy/sail-runtime-image:8.5-24@sha256:d9f7f1ee244847612252222265d71e2340417a812a15d1cfa9f3433dafb5ea75'

printf '%s\n' \
  "FROM $SAIL_BASE_IMAGE" \
  'RUN apt-get update \' \
  '    && apt-get install -y --no-install-recommends php8.5-grpc \' \
  '    && apt-get clean \' \
  '    && rm -rf /var/lib/apt/lists/*' | \
  docker build --pull \
    --tag sail-8.5/app \
    --file - \
    .

./vendor/bin/sail config >/dev/null
./vendor/bin/sail up -d
./vendor/bin/sail php --ri grpc
# ===== FIN DE LA RUTA RECOMENDADA =====
```

Al finalizar, el último comando debe mostrar la información de la extensión
gRPC. La imagen resultante queda almacenada localmente; las ejecuciones
posteriores reutilizan tanto la base descargada como la capa de gRPC. Después
se puede continuar directamente con la sección 7.

#### Opcional: construir la imagen completa localmente

Esta ruta opcional reemplaza por completo la ruta recomendada y no depende de
la imagen comunitaria. Utiliza el Dockerfile publicado por la versión de Sail
instalada en el proyecto y su argumento `PHP_EXTENSIONS`. Tarda más porque
construye localmente PHP, Node, Playwright, clientes SQL y las demás
dependencias del entorno.

```bash
# ===== INICIO: OPCIONAL, USAR EN LUGAR DE LA RUTA RECOMENDADA =====
DOCKER_HOST=unix:///dev/null \
  php artisan sail:install --with=none --no-interaction

grep -q 'PHP_EXTENSIONS:' compose.yaml || \
  sed -i "/^                WWWGROUP:/a\\                PHP_EXTENSIONS: 'grpc'" compose.yaml

./vendor/bin/sail config >/dev/null
./vendor/bin/sail build
./vendor/bin/sail up -d
./vendor/bin/sail php --ri grpc
# ===== FIN DE LA CONSTRUCCIÓN LOCAL OPCIONAL =====
```

En esta ruta opcional, el último comando también debe mostrar la información de
la extensión gRPC. La imagen completa queda almacenada localmente y se reutiliza
en los siguientes pasos.

### 7. Iniciar la aplicación

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
./vendor/bin/sail up -d
./vendor/bin/sail artisan migrate --force
./vendor/bin/sail npm run build
# ===== FIN DEL BLOQUE =====
```

La aplicación queda disponible en `http://localhost/login`. Si se define
`APP_PORT=8000` en `.env`, queda en `http://localhost:8000/login`.

Para detener los servicios:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
./vendor/bin/sail down
# ===== FIN DEL BLOQUE =====
```

### 8. Validar el resultado

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
./vendor/bin/sail composer test
./vendor/bin/sail artisan gateway:smoke
# ===== FIN DEL BLOQUE =====
```

El último comando solicita usuario y contraseña de forma interactiva y ejecuta
login, consultas protegidas, logout, validación del token revocado y las dos
pruebas negativas.

> **FIN DE LA RUTA PRINCIPAL:** si las validaciones terminaron correctamente,
> no hay que ejecutar todos los bloques siguientes en secuencia. Las secciones
> posteriores documentan variantes, pruebas repetibles y una auditoría que
> vuelve a mostrar parte del mismo proceso.

## Regla de construcción: solo scaffolding y plantillas

Ningún archivo estructural de la aplicación se creó con `touch`, heredocs ni
copias escritas a mano. Cada pieza de la aplicación parte de una plantilla o
un generador. La receta mínima enviada a `docker build` tampoco crea un archivo
en el proyecto: compone una imagen publicada con un paquete binario del
repositorio de PHP.

| Pieza | Generador, plantilla o fuente reproducible |
| --- | --- |
| Aplicación, login, rutas, Fortify, Livewire y estilos | `laravel new --livewire` |
| Cliente, contrato, excepción, controlador, middleware, comando, vista, configuración y prueba | `php artisan make:*` |
| Contratos `.proto` | reflexión del gateway con `grpcurl -proto-out-dir` |
| Clases y clientes PHP gRPC | `protoc` + `grpc_php_plugin` |
| Implementación funcional sobre los stubs | parches reproducibles con `git apply` |
| Imagen PHP con la extensión gRPC | base Sail preconstruida fijada por digest + capa binaria `php8.5-grpc`; como alternativa, Sail + `PHP_EXTENSIONS=grpc` |
| `README.md` inicial | plantilla `--add-readme` de GitHub CLI |

Los archivos generados se adaptaron para conectar esas plantillas con el flujo
del gateway. Los archivos bajo `app/Grpc` incluyen la cabecera `GENERATED CODE
-- DO NOT EDIT` y se regeneran desde los `.proto`.

## Credenciales

No hay credenciales reales confirmadas en Git. La pantalla solicita el usuario
y la contraseña y los envía directamente al RPC `Login`. El campo se llama
`email` porque así lo genera Fortify, pero su valor se utiliza como `username`
del gateway.

Para el smoke test se recomienda la entrada interactiva, que no deja la
contraseña en el historial de la terminal. Los tres bloques de esta sección son
**modalidades alternativas**: ejecutar solo uno.

```bash
# ===== INICIO: ELEGIR SOLO ESTA MODALIDAD INTERACTIVA =====
./vendor/bin/sail artisan gateway:smoke
# ===== FIN DE LA MODALIDAD INTERACTIVA =====
```

También puede indicarse solo el usuario:

```bash
# ===== INICIO: ELEGIR SOLO ESTA MODALIDAD CON USUARIO =====
./vendor/bin/sail artisan gateway:smoke \
  --username=usuario@institucion.edu.ec
# ===== FIN DE LA MODALIDAD CON USUARIO =====
```

Para automatización, definir `GATEWAY_SMOKE_USERNAME` y
`GATEWAY_SMOKE_PASSWORD` únicamente en el entorno o en un archivo `.env` no
versionado; después ejecutar:

```bash
# ===== INICIO: ELEGIR SOLO ESTA MODALIDAD AUTOMATIZADA =====
./vendor/bin/sail artisan gateway:smoke --no-prompt
# ===== FIN DE LA MODALIDAD AUTOMATIZADA =====
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
token de la sesión y llama al mismo host gRPC. El siguiente bloque representa
el flujo; es solo informativo y **no se copia ni se ejecuta**:

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
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
./vendor/bin/sail composer test
# ===== FIN DEL BLOQUE =====
```

Comprobación real de extremo a extremo contra el gateway:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
./vendor/bin/sail artisan gateway:smoke
# ===== FIN DEL BLOQUE =====
```

El smoke test valida explícitamente:

- rechazo de notificaciones sin `authorization`;
- login y presencia de ambos tokens;
- contador, listado de no leídas y recientes;
- logout remoto;
- `ValidateToken` con `isValid: false`;
- rechazo del access token revocado por notificaciones.

## Auditoría detallada de los generadores

Esta sección permite auditar el scaffolding desde un directorio vacío. Parte de
un entorno preparado con el script de dependencias indicado en la sección 1;
`laravel new` ofrece el Starter Kit de Livewire.

> **NO CONTINUAR AQUÍ AUTOMÁTICAMENTE:** esta auditoría repite pasos de la ruta
> principal. Ejecutar sus bloques solo si se quiere reconstruir y auditar el
> proyecto desde otro directorio vacío.

### 1. Starter Kit

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
laravel new login-scaffolding \
  --livewire \
  --phpunit \
  --database=sqlite \
  --no-boost \
  --no-interaction

cd login-scaffolding
# ===== FIN DEL BLOQUE =====
```

Laravel 13 ya no utiliza Breeze como Starter Kit principal. Livewire genera el
login Blade, Fortify, rutas, validaciones, rate limiting, middleware, estilos,
migraciones y pruebas base. En este proyecto se deshabilitaron registro,
recuperación, passkeys y 2FA locales porque el gateway externo es la fuente de
autenticación.

### 2. Dependencias y clases desde plantillas

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
composer require grpc/grpc:^1.81 google/protobuf:^5.35 'ext-grpc:*' \
  --ignore-platform-req=ext-grpc

php artisan make:interface Contracts/GatewayClient
php artisan make:class Services/GrpcGatewayClient
php artisan make:exception GatewayRpcException
php artisan make:controller NotificationController --invokable
php artisan make:middleware RevokeGatewaySessionOnLogout
php artisan make:command GatewaySmokeCommand
php artisan make:config gateway
php artisan make:view notifications.index
php artisan make:test GatewayAuthenticationTest

# make:view inserta una cita aleatoria; normalizarla para que el parche sea reproducible.
sed -i "/<!-- .* -->/c\\    <!-- Normalized Laravel view stub. -->" \
  resources/views/notifications/index.blade.php
# ===== FIN DEL BLOQUE =====
```

### 3. Obtener los contratos desde reflexión

Requiere `grpcurl`. Estos comandos no escriben contratos a mano: los exportan
desde el gateway desplegado.

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
mkdir -p proto

grpcurl -plaintext \
  -proto-out-dir proto \
  academia-dev.eastus2.cloudapp.azure.com:50050 \
  describe auth.v1.AuthService

grpcurl -plaintext \
  -proto-out-dir proto \
  academia-dev.eastus2.cloudapp.azure.com:50050 \
  describe notificaciones.v1.NotificationService
# ===== FIN DEL BLOQUE =====
```

`grpcurl` exporta `auth_v1.proto` y `notificaciones_v1.proto`. Antes de ejecutar
`protoc`, se agregan por comando los namespaces PHP para que las clases queden
dentro del autoload `App\\` de la plantilla Laravel:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\AuthV1";' proto/auth_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Auth\\\\V1";' proto/auth_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\NotificacionesV1";' proto/notificaciones_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Notificaciones\\\\V1";' proto/notificaciones_v1.proto
# ===== FIN DEL BLOQUE =====
```

### 4. Generar los clientes PHP

La generación se ejecuta en una imagen desechable que contiene `protoc` y
`grpc_php_plugin`. El resultado se copia a `app/Grpc` con el UID y GID del
usuario anfitrión.

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
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

composer dump-autoload --ignore-platform-req=ext-grpc
# ===== FIN DEL BLOQUE =====
```

### 5. Aplicar la implementación generada y verificada

Ejecutar el bloque de la sección
“Aplicar automáticamente la implementación funcional”. Los tres archivos
utilizados están en `/home/opc/login-scaffolding/patches` y se aplican con
`git apply`; no requieren edición manual. Si el proyecto de auditoría está en
otra ubicación, definir `PATCH_DIR` con esa ruta antes de ejecutar el bloque.

### 6. Preparar y comprobar la imagen de PHP

Ejecutar la sección
[“Preparar la imagen de PHP con gRPC”](#6-preparar-la-imagen-de-php-con-grpc) y
elegir una sola de sus rutas. La recomendada reutiliza la base Sail
preconstruida fijada por digest y construye únicamente la capa de
`php8.5-grpc`. La alternativa auditable desde las fuentes ejecuta
`./vendor/bin/sail build` con `PHP_EXTENSIONS=grpc`. Ambas terminan comprobando
el resultado con:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
./vendor/bin/sail php --ri grpc
# ===== FIN DEL BLOQUE =====
```

### 7. Crear y publicar el repositorio

```bash
# ===== INICIO: PUBLICACIÓN OPCIONAL, COPIAR TODO ESTE BLOQUE =====
gh repo create academic-mgmt-org/login-scaffolding \
  --private \
  --add-readme \
  --description "Scaffolding de login Laravel integrado con un gateway gRPC"

git add .
git commit -m "feat: add template-generated Laravel gRPC login flow"
git push -u origin main
# ===== FIN DEL BLOQUE DE PUBLICACIÓN OPCIONAL =====
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
- [Laravel Sail y extensiones adicionales de PHP](https://laravel.com/docs/13.x/sail#additional-php-extensions)
- [Argumentos de construcción de Docker Compose](https://docs.docker.com/reference/cli/docker/compose/build/)
- [Quickstart de gRPC para PHP](https://grpc.io/docs/languages/php/quickstart/)
- [Tutorial básico de gRPC para PHP](https://grpc.io/docs/languages/php/basics/)
