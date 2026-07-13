# Interfaces académicas desacopladas y plugables

Este repositorio genera aplicaciones Laravel Livewire por core asset. Cada
módulo puede ejecutarse de forma autónoma o agregarse a un host existente sin
incorporar contratos de dominios no seleccionados. Auth y la sesión forman el
núcleo común del frontend.

## Elegir una interfaz

Cada receta es autocontenida y puede ejecutarse sin consultar las demás:

| Core asset | Receta | Ruta resultante |
|---|---|---|
| Autenticación y sesiones | [`docs/academico-login.md`](docs/academico-login.md) | `/academico/sesiones` |
| Gestión de usuarios | [`docs/academico-usuarios.md`](docs/academico-usuarios.md) | `/academico/usuarios` |
| Matrículas | [`docs/academico-matriculas.md`](docs/academico-matriculas.md) | `/academico/matriculas` |
| Calificaciones | [`docs/academico-calificaciones.md`](docs/academico-calificaciones.md) | `/academico/calificaciones` |
| Solicitudes académicas | [`docs/academico-solicitudes.md`](docs/academico-solicitudes.md) | `/academico/solicitudes` |
| Notificaciones | [`docs/academico-notificaciones.md`](docs/academico-notificaciones.md) | `/academico/notificaciones` |

Para Notificaciones, por ejemplo, basta con ejecutar el bloque de
[`docs/academico-notificaciones.md`](docs/academico-notificaciones.md). El
resultado no contiene clientes, configuración ni flujos de Usuarios,
Matrículas, Calificaciones o Solicitudes.

Si ya existe una aplicación `academico-login`, la receta de Notificaciones la
detecta y agrega `/academico/notificaciones` dentro del mismo frontend y del
mismo Compose. Si no existe, crea una aplicación autónoma con
`/academico/login` incluido.

## Cómo se genera

Los archivos estructurales no se mantienen como copias manuales. El proceso es:

1. Laravel Installer crea la aplicación desde el Starter Kit oficial de
   Livewire fijado en el commit
   `1f84e33e6bf6c95f9925e3e023bce71341ced005`.
2. `php artisan make:*` crea la interfaz PHP, servicio, excepción, proveedor,
   middleware, controladores, configuraciones, vistas y prueba.
3. `patches/0001-interface-core.patch` completa esos stubs con el
   cliente gRPC genérico y la sesión remota.
4. `patches/0002-pluggable-modules.patch` habilita el registro y las rutas de
   varios módulos sobre una sola sesión.
5. Se aplica el parche del módulo solicitado; ejecuciones posteriores pueden
   agregar otros parches de módulo al mismo host.
6. Los `.proto` se obtienen de revisiones Git fijadas, se validan por SHA-256 y
   `protoc` genera los clientes PHP. Siempre se compila Auth; adicionalmente se
   compila solo el contrato funcional seleccionado.
7. Sail genera `compose.yaml` y se prepara PHP 8.5 con la extensión gRPC solo
   cuando la aplicación todavía no dispone de runtime.

`academico-login` es una dependencia técnica de las otras cinco interfaces:
permite login, JWT, refresh y logout. Esto no instala otra interfaz funcional.

## Usar el selector en una aplicación ya creada

Para auditar la selección sin modificar archivos:

```bash
./setup/install-interface-module.sh \
  academico-notificaciones \
  /ruta/a/la-aplicacion \
  --plan
```

Para instalarla:

```bash
./setup/install-interface-module.sh \
  academico-notificaciones \
  /ruta/a/la-aplicacion
```

La aplicación debe provenir de la revisión del Starter Kit indicada. El
instalador es reejecutable y acumulativo: puede actualizar el mismo módulo o
agregar otro a la aplicación. También migra hosts generados con el formato
anterior, cuyo primer módulo permanece en `config/academic-module.php`.
`prepare-interface-runtime.sh` solo debe ejecutarse cuando se trate de una
aplicación nueva que todavía no tenga `compose.yaml`; un host existente conserva
su propio runtime.

Para el flujo automático de Notificaciones:

```bash
./setup/install-notifications-interface.sh --plan
./setup/install-notifications-interface.sh
```

## Estructura del repositorio

```text
docs/                         una receta autocontenida por core asset
patches/                      núcleo común, capa plugable y módulos acumulativos
setup/install-interface-dependencies.sh
setup/install-interface-module.sh
setup/install-notifications-interface.sh
setup/prepare-interface-runtime.sh
locks/                        locks reproducibles de Composer y npm
tests/modular-scaffolding.sh  auditoría del selector y del aislamiento
```

## Verificación

La comprobación estática del repositorio no necesita crear una aplicación:

```bash
./tests/modular-scaffolding.sh
```

Además, cada instalación ejecuta `AcademicInterfaceTest`. Esa prueba valida la
sesión, el allow-list de RPCs, el formulario de cada acción y que el módulo no
registre dominios funcionales ajenos.
