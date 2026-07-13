# Sistema académico desde scaffolding

Aplicación Laravel reproducible contra un gateway gRPC. La base proviene del
Starter Kit oficial de Livewire y todas las interfaces adicionales nacen de
generadores de Artisan. Los parches de `patches/` completan automáticamente
los stubs; ningún paso de la ruta principal requiere editar archivos a mano.

El proyecto ejecuta, en este orden:

1. `auth.v1.AuthService/Login`.
2. `notificaciones.v1.NotificationService/CountUnread`.
3. `ListNotifications` para las no leídas y `RecentNotifications` para las
   recientes, siempre con `authorization: Bearer <JWT>`.
4. `auth.v1.AuthService/Logout` con access token y refresh token.
5. Las pruebas negativas sin login y con el token revocado.
6. Alta y regularización de estudiantes mediante `usuarios.v1.*`.
7. Inscripción, ajuste y cancelación mediante `matriculas.v1.*`.
8. Registro, corrección y publicación de notas mediante
   `calificaciones.v1.*`.
9. Creación, revisión documental y resolución de becas mediante
   `solicitudes.v1.*`.
10. Recuperación de contraseña mediante `ForgotPassword` y `ResetPassword`.

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

## Crear la aplicación desde cero con plantillas predefinidas

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
LIVEWIRE_STARTER='laravel/livewire-starter-kit:dev-main#1f84e33e6bf6c95f9925e3e023bce71341ced005'

laravel new sistema-login \
  --using="$LIVEWIRE_STARTER" \
  --phpunit \
  --database=sqlite \
  --npm \
  --no-boost \
  --no-interaction

cd sistema-login
# ===== FIN DEL BLOQUE =====
```

La revisión del Starter Kit queda fijada por su SHA de Git y el preparador fija
Laravel Installer 5.28.1. Una actualización de `dev-main` o del instalador no
puede cambiar silenciosamente los stubs que reciben los parches.

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

# Restaurar los locks versionados para que Composer y npm instalen exactamente
# los mismos bytes aunque se publiquen nuevas dependencias transitivas.
LOCK_TEMPLATE_DIR="${LOCK_TEMPLATE_DIR:-../templates/app-locks}"
cp "$LOCK_TEMPLATE_DIR/composer.lock" composer.lock
cp "$LOCK_TEMPLATE_DIR/package-lock.json" package-lock.json
composer install --ignore-platform-req=ext-grpc --no-interaction

php artisan make:interface Contracts/GatewayClient --no-interaction
php artisan make:class Services/GrpcGatewayClient --no-interaction
php artisan make:exception GatewayRpcException --no-interaction
php artisan make:controller NotificationController --invokable --no-interaction
php artisan make:controller GatewayDashboardController --no-interaction
php artisan make:controller GatewayFlowController --no-interaction
php artisan make:controller GatewayPasswordController --no-interaction
php artisan make:controller GatewaySessionAuditController --invokable --no-interaction
php artisan make:middleware RevokeGatewaySessionOnLogout --no-interaction
php artisan make:middleware EnsureGatewaySession --no-interaction
php artisan make:command GatewaySmokeCommand --no-interaction
php artisan make:config gateway --no-interaction
php artisan make:config gateway-flows --no-interaction
php artisan make:view notifications.index --no-interaction
php artisan make:view notifications.session-audit --no-interaction
php artisan make:view dashboard.index --no-interaction
php artisan make:view flows.show --no-interaction
php artisan make:test GatewayAuthenticationTest --no-interaction
php artisan make:test GatewayFlowsTest --no-interaction
php artisan make:test GatewayPasswordRecoveryTest --no-interaction
php artisan make:test GatewaySessionAuditTest --no-interaction

# make:view inserta una cita aleatoria; normalizarla para que el parche sea reproducible.
for VIEW in \
  resources/views/notifications/index.blade.php \
  resources/views/notifications/session-audit.blade.php \
  resources/views/dashboard/index.blade.php \
  resources/views/flows/show.blade.php; do
  sed -i '/<!-- .* -->/c\    <!-- Normalized Laravel view stub. -->' "$VIEW"
done
# ===== FIN DEL BLOQUE =====
```

Todos esos archivos nacen de stubs mantenidos por Laravel. La implementación
completa los stubs para delegar el login de Fortify al gateway, guardar los
tokens en la sesión del servidor, consultar notificaciones y ejecutar desde la
interfaz cada bloque de `FLUJO_GATEWAY`. Las respuestas encadenan en la sesión
los identificadores de estudiante, matrícula, materia, componentes, notas y
solicitudes; los tokens nunca se envían al navegador.

La omisión de `ext-grpc` solo permite completar el scaffolding con el PHP del
anfitrión. La imagen se valida más adelante y no ejecuta la aplicación si la
extensión no quedó cargada.

### 4. Generar contratos y clientes gRPC

Los `.proto` tampoco se redactan a mano. Auth y Notificaciones se exportan
desde la reflexión del gateway. Como el despliegue verificado todavía no
publica los contratos funcionales de los otros cuatro dominios, sus fuentes
canónicas se obtienen automáticamente con Git desde los repositorios de cada
core asset, incluidos los repositorios privados accesibles para el operador.
Finalmente `protoc` genera todas las clases y clientes PHP.

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

PROTO_SOURCES="$(mktemp -d)"
cleanup_proto_sources() { rm -rf "$PROTO_SOURCES"; }
trap cleanup_proto_sources EXIT

USUARIOS_REF='782edab9d6905b93b3addcd364b53034973baf1f'
MATRICULAS_REF='a1eb14a96a747ec42649275251d4a0c1267edab5'
CALIFICACIONES_REF='bdc6215603dc50ea2266120fa454614929b47fb1'
SOLICITUDES_REF='f93079c090480dfb0563cf9e15a03e59ba906a38'

clone_at_ref() {
  local repository="$1"
  local revision="$2"
  local destination="$3"
  git init -q "$destination"
  git -C "$destination" remote add origin "$repository"
  git -C "$destination" fetch -q --depth=1 origin "$revision"
  git -C "$destination" checkout -q --detach FETCH_HEAD
}

clone_at_ref https://github.com/academic-mgmt-org/academico-usuarios.git "$USUARIOS_REF" "$PROTO_SOURCES/usuarios"
clone_at_ref https://github.com/academic-mgmt-org/academico-matriculas.git "$MATRICULAS_REF" "$PROTO_SOURCES/matriculas"
clone_at_ref https://github.com/academic-mgmt-org/academico-calificaciones.git "$CALIFICACIONES_REF" "$PROTO_SOURCES/calificaciones"
clone_at_ref https://github.com/academic-mgmt-org/academico-solicitudes.git "$SOLICITUDES_REF" "$PROTO_SOURCES/solicitudes"

cp "$PROTO_SOURCES/usuarios/proto/usuarios/v1/usuarios.proto" proto/usuarios_v1.proto
cp "$PROTO_SOURCES/matriculas/proto/matriculas/v1/matriculas.proto" proto/matriculas_v1.proto
cp "$PROTO_SOURCES/calificaciones/proto/calificaciones/v1/calificaciones.proto" proto/calificaciones_v1.proto
cp "$PROTO_SOURCES/solicitudes/proto/solicitudes/v1/solicitudes.proto" proto/solicitudes_v1.proto

cleanup_proto_sources
trap - EXIT

sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\AuthV1";' proto/auth_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Auth\\\\V1";' proto/auth_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\NotificacionesV1";' proto/notificaciones_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Notificaciones\\\\V1";' proto/notificaciones_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\UsuariosV1";' proto/usuarios_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Usuarios\\\\V1";' proto/usuarios_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\MatriculasV1";' proto/matriculas_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Matriculas\\\\V1";' proto/matriculas_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\CalificacionesV1";' proto/calificaciones_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Calificaciones\\\\V1";' proto/calificaciones_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\SolicitudesV1";' proto/solicitudes_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Solicitudes\\\\V1";' proto/solicitudes_v1.proto

# La reflexión y los repositorios son entradas externas. Estos hashes impiden
# continuar silenciosamente si alguno deja de producir los contratos fijados.
sha256sum --check <<'PROTO_HASHES'
43db2972d31d8d9cb1cf52a89578e31b21acf264c14f721fb44bfa330beef7a1  proto/auth_v1.proto
fcbd4ae7cd5c36095a2381643a5b80752ce750595c45081900c962d2f3a58ca9  proto/calificaciones_v1.proto
dd51440b815140180f6688b447e85cca1dc93cd0363cdce13665cc62d7bd53c8  proto/matriculas_v1.proto
7570c6f665489f8d9559d6e80cd4b433645d4bb6aac091b2392a6ff4fb279af9  proto/notificaciones_v1.proto
e8c2025cd0d8f1d95440be062c4f7728cdf4339aaf5fceefe3291b25494203c5  proto/solicitudes_v1.proto
d316abd3a3798cdd29fc29a554352c57ab798a304220655690678c72670f5c46  proto/usuarios_v1.proto
PROTO_HASHES

WORKSPACE_PATH="$PWD"
case "$(uname -s)" in
  MINGW* | MSYS*) WORKSPACE_PATH="$(pwd -W)" ;;
esac

MSYS_NO_PATHCONV=1 docker run --rm \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -v "$WORKSPACE_PATH:/workspace" \
  -w /workspace \
  debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df \
  sh -lc '
    apt-get update >/dev/null &&
    apt-get install -y --no-install-recommends \
      protobuf-compiler=3.21.12-3+deb12u1 \
      protobuf-compiler-grpc=1.51.1-3+b1 >/dev/null &&
    mkdir -p /tmp/generated &&
    protoc --proto_path=proto \
      --php_out=/tmp/generated \
      --grpc_out=/tmp/generated \
      --plugin=protoc-gen-grpc=/usr/bin/grpc_php_plugin \
      proto/auth_v1.proto \
      proto/notificaciones_v1.proto \
      proto/usuarios_v1.proto \
      proto/matriculas_v1.proto \
      proto/calificaciones_v1.proto \
      proto/solicitudes_v1.proto &&
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

  GIT_APPLY=(git apply)
  if PROJECT_PREFIX="$(git rev-parse --show-prefix 2>/dev/null)" &&
    [[ -n "$PROJECT_PREFIX" ]]; then
    GIT_APPLY+=(--directory="$PROJECT_PREFIX")
  fi

  git_apply() {
    local patch_file="$1"
    shift
    tr -d '\r' < "$patch_file" | "${GIT_APPLY[@]}" "$@"
  }

  PATCH_DIR="${PATCH_DIR:-../patches}"
  PATCHES=(
    "$PATCH_DIR/0001-gateway-client.patch"
    "$PATCH_DIR/0002-fortify-login-flow.patch"
    "$PATCH_DIR/0003-tests-and-analysis.patch"
    "$PATCH_DIR/0004-disable-test-timeout.patch"
    "$PATCH_DIR/0005-academic-gateway-interfaces.patch"
    "$PATCH_DIR/0006-deterministic-tailwind-source.patch"
  )

  for PATCH_FILE in "${PATCHES[@]}"; do
    if git_apply "$PATCH_FILE" --reverse --check >/dev/null 2>&1; then
      echo "Ya aplicado: $(basename "$PATCH_FILE")"
    else
      git_apply "$PATCH_FILE" --check
      git_apply "$PATCH_FILE"
      echo "Aplicado: $(basename "$PATCH_FILE")"
    fi
  done

  if ! grep -q '^GATEWAY_GRPC_HOST=' .env; then
    cp .env.example .env
    php artisan key:generate --force
  fi

  ../setup/normalize-generated-app.sh .
  composer dump-autoload --ignore-platform-req=ext-grpc
  php artisan optimize:clear
)
# ===== FIN DEL BLOQUE =====
```

`GIT_APPLY` incorpora automáticamente el prefijo del proyecto cuando
`sistema-login` está dentro de otro repositorio Git. Así, rutas del parche como
`app/` y `config/` se aplican dentro de `sistema-login` en vez de ser ignoradas
silenciosamente por Git. Si el proyecto es la raíz del repositorio o está fuera
de uno, el comando conserva el comportamiento normal de `git apply`.

`git_apply` normaliza los finales de línea antes de cada comprobación. Esto
evita que `core.autocrlf=true` convierta los parches a CRLF en Windows mientras
los archivos generados por Laravel permanecen con LF. `.gitattributes` también
conserva los parches con LF en clones nuevos.

Los parches se separan por responsabilidad: cliente gRPC, integración con
Fortify, pruebas/análisis estático, interfaces de los flujos académicos y
compilación determinista de Tailwind. El quinto parche completa automáticamente
los controladores, middleware, configuración, vistas y pruebas creados en la
sección 3; el sexto desactiva la detección implícita de la raíz Git y conserva
solo las fuentes CSS declaradas. No incluyen `.env`, credenciales, tokens, los
`.proto` ni las clases generadas de `app/Grpc`.

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
genera en `compose.yaml`, por lo que `docker compose up --no-build` utiliza la
imagen preparada sin reconstruir localmente las dependencias del entorno. Los
comandos posteriores invocan Docker Compose directamente para ser compatibles
con Git Bash; no ejecutan el wrapper de Sail, que rechaza el entorno MINGW.
Las sustituciones de `WWWUSER` y `WWWGROUP` usan `1000` solo como valor
predeterminado para el motor en WSL; pueden sobrescribirse en `.env` cuando el
usuario del motor Docker tenga otros identificadores.

```bash
# ===== INICIO: RUTA RECOMENDADA, COPIAR Y EJECUTAR TODO =====
DOCKER_HOST=unix:///dev/null \
  php artisan sail:install --with=none --no-interaction

grep -q 'WEBSERVER: cli' compose.yaml || \
  sed -i "/WWWUSER:/i\\            WWWGROUP: '\${WWWGROUP}'\\n            WEBSERVER: cli" compose.yaml

sed -i \
  -e "s/'\${WWWUSER}'/'\${WWWUSER:-1000}'/g" \
  -e "s/'\${WWWGROUP}'/'\${WWWGROUP:-1000}'/g" \
  compose.yaml

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

docker compose config >/dev/null
docker compose up -d --no-build
docker compose exec -T laravel.test php --ri grpc
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

sed -i \
  -e "s/'\${WWWUSER}'/'\${WWWUSER:-1000}'/g" \
  -e "s/'\${WWWGROUP}'/'\${WWWGROUP:-1000}'/g" \
  compose.yaml

docker compose config >/dev/null
docker compose build
docker compose up -d --no-build
docker compose exec -T laravel.test php --ri grpc
# ===== FIN DE LA CONSTRUCCIÓN LOCAL OPCIONAL =====
```

En esta ruta opcional, el último comando también debe mostrar la información de
la extensión gRPC. La imagen completa queda almacenada localmente y se reutiliza
en los siguientes pasos.

### 7. Iniciar la aplicación

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
docker compose up -d --no-build
docker compose exec -T laravel.test php artisan migrate --force
docker compose exec -T laravel.test npm ci
docker compose exec -T laravel.test npm run build
../setup/verify-generated-app.sh .
# ===== FIN DEL BLOQUE =====
```

`npm ci` se ejecuta dentro del contenedor antes de compilar para instalar las
dependencias nativas de Linux. No se debe reutilizar el directorio
`node_modules` creado por npm en Windows, porque los bindings de Rolldown son
específicos de cada sistema operativo.

El último comando calcula nuevamente el inventario SHA-256 y lo compara con
`templates/app.sha256`. La construcción solo continúa si los archivos fuente,
contratos, lockfiles, `compose.yaml` y los artefactos de `public/build` son
idénticos byte a byte a la aplicación verificada. La comparación excluye
únicamente estado que debe variar por seguridad o durante la ejecución:
`.env`, bases SQLite, `vendor`, `node_modules`, cachés de Laravel, logs y cachés
de PHPUnit. Los locks incluidos fijan el contenido instalable de las dos
carpetas de dependencias excluidas.

La configuración generada define `APP_PORT=8000`, por lo que la aplicación
queda disponible en **` http://localhost:8000/login`**. No usar
`http://localhost/login`: esa dirección utiliza el puerto 80 del anfitrión y
puede responder desde otro servicio local, como Apache, en vez del contenedor.

Para detener los servicios:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
docker compose down
# ===== FIN DEL BLOQUE =====
```

### 8. Validar el resultado

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
docker compose exec -T laravel.test composer test
npm ci --prefix ..
npm --prefix .. run test:login
npm --prefix .. run test:flows
docker compose exec laravel.test php artisan gateway:smoke
# ===== FIN DEL BLOQUE =====
```

La prueba de navegador usa `http://localhost:8000/login` y Microsoft Edge de
forma predeterminada en Windows. `LOGIN_URL`, `LOGIN_EMAIL`, `LOGIN_PASSWORD`,
`LOGIN_TIMEOUT_MS` y `PLAYWRIGHT_CHANNEL` permiten sobrescribir esos valores
sin editar el script. El timeout predeterminado es de 120 segundos para admitir
proyectos montados desde directorios sincronizados de Windows.
El resultado debe incluir `"success": true` y terminar en `/dashboard`.

`test:flows` abre la interfaz y ejecuta, en orden, los cinco documentos de
`FLUJO_GATEWAY` incluidos en esta validación. No ejecuta
`CONTRASEÑA_OLVIDADA.md`, porque ese recorrido requiere comprobar el correo real.
Las credenciales se pueden cambiar con `ADMIN_EMAIL`, `ADMIN_PASSWORD`,
`TEACHER_EMAIL`, `TEACHER_PASSWORD`, `LOGIN_EMAIL` y `LOGIN_PASSWORD`; la URL y
el timeout comunes aceptan `INTERFACE_URL` y `FLOW_TIMEOUT_MS`.

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
| Aplicación, login, rutas, Fortify, Livewire y estilos | `laravel new --using=<Starter Kit fijado por SHA>` |
| Cliente, contrato, excepción, controlador, middleware, comando, vista, configuración y prueba | `php artisan make:*` |
| Contratos `.proto` | reflexión con `grpcurl` para servicios publicados y `git clone` de los repositorios canónicos para contratos aún no publicados |
| Clases y clientes PHP gRPC | `protoc` + `grpc_php_plugin` |
| Implementación funcional sobre los stubs | parches reproducibles con `git apply` |
| Locks e inventario byte a byte | `templates/app-locks/`, normalización LF y `templates/app.sha256` |
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
docker compose exec laravel.test php artisan gateway:smoke
# ===== FIN DE LA MODALIDAD INTERACTIVA =====
```

También puede indicarse solo el usuario:

```bash
# ===== INICIO: ELEGIR SOLO ESTA MODALIDAD CON USUARIO =====
docker compose exec laravel.test php artisan gateway:smoke \
  --username=usuario@institucion.edu.ec
# ===== FIN DE LA MODALIDAD CON USUARIO =====
```

Para automatización, definir `GATEWAY_SMOKE_USERNAME` y
`GATEWAY_SMOKE_PASSWORD` en el archivo `.env` no versionado; el contenedor lee
ese archivo montado desde el proyecto. Después ejecutar:

```bash
# ===== INICIO: ELEGIR SOLO ESTA MODALIDAD AUTOMATIZADA =====
docker compose exec -T laravel.test \
  php artisan gateway:smoke --no-prompt
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

### Panel y flujos académicos

`GET /dashboard` presenta los cuatro recorridos de negocio. Cada acción usa un
catálogo cerrado de RPCs y un formulario generado desde `config/gateway-flows.php`.
Cuando una respuesta contiene un identificador funcional, el controlador lo
guarda en la sesión cifrada y lo precarga en el siguiente bloque. Así puede
ejecutarse desde el navegador la cadena `Usuarios -> Matrículas ->
Calificaciones`, además del expediente independiente de Solicitudes.

Si el gateway aún no publica un contrato, la interfaz conserva el contexto y
muestra el código gRPC recibido —por ejemplo, `12 Unimplemented`— para
distinguir esa condición de un error de formulario. El cliente web nunca envía
API keys; el gateway continúa siendo responsable de inyectarlas.

### Notificaciones

`GET /notificaciones` exige una sesión local y una sesión gateway válidas. El
controlador obtiene el access token de la sesión y llama al mismo host gRPC. El
siguiente bloque representa el flujo; es solo informativo y **no se copia ni
se ejecuta**:

```text
CountUnread -> ListNotifications(estado=no_leido, limit=unreadCount)
            -> RecentNotifications(limit=5)
```

El cliente envía `authorization: Bearer <JWT>` y no envía `x-api-key`; esa clave
la agrega el gateway al reenviar la petición.

El botón **Auditar cierre de sesión** ejecuta desde la interfaz la parte final
del flujo: valida el token vigente, consulta notificaciones, cierra la sesión
remota y comprueba que el token revocado y las peticiones sin autorización sean
rechazados. Al terminar invalida también la sesión local y no muestra tokens en
el HTML.

### Contraseña olvidada

`GET /forgot-password` solicita el enlace con `AuthService/ForgotPassword`.
El enlace más reciente abre `GET /reset-password?token=...&email=...` y el
formulario envía la nueva clave directamente a `AuthService/ResetPassword` con
`passwordEncoding=plain`. No interviene el broker local de contraseñas.

### Logout

El `POST /logout` generado por Fortify pasa primero por
`RevokeGatewaySessionOnLogout`. Ese middleware llama a `AuthService/Logout`
con ambos tokens y luego Fortify elimina la sesión local, incluso si el gateway
no está disponible.

## Pruebas

Pruebas aisladas, sin usar credenciales ni la red:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
docker compose exec -T laravel.test composer test
# ===== FIN DEL BLOQUE =====
```

Comprobación real de extremo a extremo contra el gateway:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
docker compose exec laravel.test php artisan gateway:smoke
# ===== FIN DEL BLOQUE =====
```

Pruebas de cada flujo desde la interfaz generada:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
npm ci --prefix ..
npm --prefix .. run test:flow:login-notifications
npm --prefix .. run test:flow:users
npm --prefix .. run test:flow:enrollments
npm --prefix .. run test:flow:grades
npm --prefix .. run test:flow:requests
# ===== FIN DEL BLOQUE =====
```

Como alternativa, ejecutar los cinco scripts en secuencia con un solo comando
en lugar de los cinco `test:flow:*` anteriores:

```bash
npm --prefix .. run test:flows
```

Cada script inicia sesión y acciona formularios reales de Blade con Playwright;
no llama directamente a gRPC. Termina con código distinto de cero cuando falta
una interfaz, una captura de contexto o una respuesta no coincide con el flujo
documentado. `HEADLESS=false` permite observar la ejecución en el navegador.

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
LIVEWIRE_STARTER='laravel/livewire-starter-kit:dev-main#1f84e33e6bf6c95f9925e3e023bce71341ced005'

laravel new sistema-login \
  --using="$LIVEWIRE_STARTER" \
  --phpunit \
  --database=sqlite \
  --npm \
  --no-boost \
  --no-interaction

cd sistema-login
# ===== FIN DEL BLOQUE =====
```

Laravel 13 ya no utiliza Breeze como Starter Kit principal. Livewire genera el
login Blade, Fortify, rutas, validaciones, rate limiting, middleware, estilos,
migraciones y pruebas base. En este proyecto se deshabilitaron registro,
recuperación mediante el broker local, passkeys y 2FA porque el gateway externo
es la fuente de autenticación; el quinto parche agrega la recuperación remota
con los RPCs de Auth.

### 2. Dependencias y clases desde plantillas

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
composer require grpc/grpc:^1.81 google/protobuf:^5.35 'ext-grpc:*' \
  --ignore-platform-req=ext-grpc

LOCK_TEMPLATE_DIR="${LOCK_TEMPLATE_DIR:-../templates/app-locks}"
cp "$LOCK_TEMPLATE_DIR/composer.lock" composer.lock
cp "$LOCK_TEMPLATE_DIR/package-lock.json" package-lock.json
composer install --ignore-platform-req=ext-grpc --no-interaction

php artisan make:interface Contracts/GatewayClient
php artisan make:class Services/GrpcGatewayClient
php artisan make:exception GatewayRpcException
php artisan make:controller NotificationController --invokable
php artisan make:controller GatewayDashboardController
php artisan make:controller GatewayFlowController
php artisan make:controller GatewayPasswordController
php artisan make:controller GatewaySessionAuditController --invokable
php artisan make:middleware RevokeGatewaySessionOnLogout
php artisan make:middleware EnsureGatewaySession
php artisan make:command GatewaySmokeCommand
php artisan make:config gateway
php artisan make:config gateway-flows
php artisan make:view notifications.index
php artisan make:view notifications.session-audit
php artisan make:view dashboard.index
php artisan make:view flows.show
php artisan make:test GatewayAuthenticationTest
php artisan make:test GatewayFlowsTest
php artisan make:test GatewayPasswordRecoveryTest
php artisan make:test GatewaySessionAuditTest

# make:view inserta una cita aleatoria; normalizarla para que el parche sea reproducible.
for VIEW in \
  resources/views/notifications/index.blade.php \
  resources/views/notifications/session-audit.blade.php \
  resources/views/dashboard/index.blade.php \
  resources/views/flows/show.blade.php; do
  sed -i "/<!-- .* -->/c\\    <!-- Normalized Laravel view stub. -->" "$VIEW"
done
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

PROTO_SOURCES="$(mktemp -d)"
trap 'rm -rf "$PROTO_SOURCES"' EXIT
USUARIOS_REF='782edab9d6905b93b3addcd364b53034973baf1f'
MATRICULAS_REF='a1eb14a96a747ec42649275251d4a0c1267edab5'
CALIFICACIONES_REF='bdc6215603dc50ea2266120fa454614929b47fb1'
SOLICITUDES_REF='f93079c090480dfb0563cf9e15a03e59ba906a38'

clone_at_ref() {
  local repository="$1"
  local revision="$2"
  local destination="$3"
  git init -q "$destination"
  git -C "$destination" remote add origin "$repository"
  git -C "$destination" fetch -q --depth=1 origin "$revision"
  git -C "$destination" checkout -q --detach FETCH_HEAD
}

clone_at_ref https://github.com/academic-mgmt-org/academico-usuarios.git "$USUARIOS_REF" "$PROTO_SOURCES/usuarios"
clone_at_ref https://github.com/academic-mgmt-org/academico-matriculas.git "$MATRICULAS_REF" "$PROTO_SOURCES/matriculas"
clone_at_ref https://github.com/academic-mgmt-org/academico-calificaciones.git "$CALIFICACIONES_REF" "$PROTO_SOURCES/calificaciones"
clone_at_ref https://github.com/academic-mgmt-org/academico-solicitudes.git "$SOLICITUDES_REF" "$PROTO_SOURCES/solicitudes"
cp "$PROTO_SOURCES/usuarios/proto/usuarios/v1/usuarios.proto" proto/usuarios_v1.proto
cp "$PROTO_SOURCES/matriculas/proto/matriculas/v1/matriculas.proto" proto/matriculas_v1.proto
cp "$PROTO_SOURCES/calificaciones/proto/calificaciones/v1/calificaciones.proto" proto/calificaciones_v1.proto
cp "$PROTO_SOURCES/solicitudes/proto/solicitudes/v1/solicitudes.proto" proto/solicitudes_v1.proto
rm -rf "$PROTO_SOURCES"
trap - EXIT
# ===== FIN DEL BLOQUE =====
```

`grpcurl` exporta los dos contratos publicados y Git obtiene los cuatro
contratos canónicos restantes. Antes de ejecutar `protoc`, se agregan por
comando los namespaces PHP para que las clases queden dentro del autoload
`App\\` de la plantilla Laravel:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\AuthV1";' proto/auth_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Auth\\\\V1";' proto/auth_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\NotificacionesV1";' proto/notificaciones_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Notificaciones\\\\V1";' proto/notificaciones_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\UsuariosV1";' proto/usuarios_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Usuarios\\\\V1";' proto/usuarios_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\MatriculasV1";' proto/matriculas_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Matriculas\\\\V1";' proto/matriculas_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\CalificacionesV1";' proto/calificaciones_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Calificaciones\\\\V1";' proto/calificaciones_v1.proto
sed -i '4i\option php_metadata_namespace = "App\\\\Grpc\\\\GPBMetadata\\\\SolicitudesV1";' proto/solicitudes_v1.proto
sed -i '4i\option php_namespace = "App\\\\Grpc\\\\Solicitudes\\\\V1";' proto/solicitudes_v1.proto

sha256sum --check <<'PROTO_HASHES'
43db2972d31d8d9cb1cf52a89578e31b21acf264c14f721fb44bfa330beef7a1  proto/auth_v1.proto
fcbd4ae7cd5c36095a2381643a5b80752ce750595c45081900c962d2f3a58ca9  proto/calificaciones_v1.proto
dd51440b815140180f6688b447e85cca1dc93cd0363cdce13665cc62d7bd53c8  proto/matriculas_v1.proto
7570c6f665489f8d9559d6e80cd4b433645d4bb6aac091b2392a6ff4fb279af9  proto/notificaciones_v1.proto
e8c2025cd0d8f1d95440be062c4f7728cdf4339aaf5fceefe3291b25494203c5  proto/solicitudes_v1.proto
d316abd3a3798cdd29fc29a554352c57ab798a304220655690678c72670f5c46  proto/usuarios_v1.proto
PROTO_HASHES
# ===== FIN DEL BLOQUE =====
```

### 4. Generar los clientes PHP

La generación se ejecuta en una imagen desechable que contiene `protoc` y
`grpc_php_plugin`. El resultado se copia a `app/Grpc` con el UID y GID del
usuario anfitrión.

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
WORKSPACE_PATH="$PWD"
case "$(uname -s)" in
  MINGW* | MSYS*) WORKSPACE_PATH="$(pwd -W)" ;;
esac

MSYS_NO_PATHCONV=1 docker run --rm \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -v "$WORKSPACE_PATH:/workspace" \
  -w /workspace \
  debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df \
  sh -lc '
    apt-get update >/dev/null &&
    apt-get install -y --no-install-recommends \
      protobuf-compiler=3.21.12-3+deb12u1 \
      protobuf-compiler-grpc=1.51.1-3+b1 >/dev/null &&
    mkdir -p /tmp/generated &&
    protoc --proto_path=proto \
      --php_out=/tmp/generated \
      --grpc_out=/tmp/generated \
      --plugin=protoc-gen-grpc=/usr/bin/grpc_php_plugin \
      proto/auth_v1.proto \
      proto/notificaciones_v1.proto \
      proto/usuarios_v1.proto \
      proto/matriculas_v1.proto \
      proto/calificaciones_v1.proto \
      proto/solicitudes_v1.proto &&
    cp -R /tmp/generated/App/Grpc app/ &&
    chown -R "$HOST_UID:$HOST_GID" app/Grpc
  '

composer dump-autoload --ignore-platform-req=ext-grpc
# ===== FIN DEL BLOQUE =====
```

### 5. Aplicar la implementación generada y verificada

Ejecutar el bloque de la sección
“Aplicar automáticamente la implementación funcional”. Los seis archivos
utilizados están en `/home/opc/login-scaffolding/patches` y se aplican con
`git apply`; no requieren edición manual. Si el proyecto de auditoría está en
otra ubicación, definir `PATCH_DIR` con esa ruta antes de ejecutar el bloque.

### 6. Preparar y comprobar la imagen de PHP

Ejecutar la sección
[“Preparar la imagen de PHP con gRPC”](#6-preparar-la-imagen-de-php-con-grpc) y
elegir una sola de sus rutas. La recomendada reutiliza la base Sail
preconstruida fijada por digest y construye únicamente la capa de
`php8.5-grpc`. La alternativa auditable desde las fuentes ejecuta
`docker compose build` con `PHP_EXTENSIONS=grpc`. Ambas terminan comprobando
el resultado con:

```bash
# ===== INICIO: COPIAR Y EJECUTAR TODO ESTE BLOQUE =====
docker compose exec -T laravel.test php --ri grpc
# ===== FIN DEL BLOQUE =====
```

### 7. Crear y publicar el repositorio

```bash
# ===== INICIO: PUBLICACIÓN OPCIONAL, COPIAR TODO ESTE BLOQUE =====
gh repo create academic-mgmt-org/login-scaffolding \
  --private \
  --add-readme \
  --description "Sistema académico Laravel generado desde plantillas y conectado al gateway gRPC"

git add .
git commit -m "feat: add template-generated academic gateway flows"
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
- El cliente implementa explícitamente los 63 RPCs documentados y el ejecutor
  genérico usa un catálogo cerrado; el nombre del servicio nunca se toma
  directamente del request HTTP.
- Las API keys permanecen en el gateway. Los formularios solo envían datos de
  dominio y, para Usuarios y Notificaciones, el bearer token de la sesión.
- Contraseñas y tokens se eliminan de la representación del payload guardada
  como último resultado del flujo.
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
