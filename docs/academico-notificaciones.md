# Interfaz plugable: academico-notificaciones

Esta receta instala únicamente Notificaciones: creación, bandeja, recientes,
contador de no leídas, lectura individual, lectura masiva y envío de correo.
Auth se compila solo como dependencia técnica para obtener la identidad y la
sesión; no se instalan Usuarios, Matrículas, Calificaciones ni Solicitudes.

## Resolver el host e instalar

Ejecutar desde la raíz de este repositorio:

```bash
./setup/install-notifications-interface.sh --plan
./setup/install-notifications-interface.sh
```

El instalador elige uno de estos modos:

- Si encuentra `interfaz-academico-login` en `WORK_ROOT`, instala el contrato,
  configuración y ruta de Notificaciones dentro de esa misma aplicación. Se
  conserva la sesión abierta y se reutiliza su único `compose.yaml`.
- Si no encuentra el host Login, crea `interfaz-academico-notificaciones` como
  aplicación autónoma, incorpora el núcleo Auth/Login y prepara su propio
  runtime Sail.

La raíz predeterminada es `../interfaces-academicas`, relativa a este
repositorio. Para un host en otra ubicación, indicar la ruta de forma explícita:

```bash
LOGIN_APP_DIR=/ruta/interfaz-academico-login \
  ./setup/install-notifications-interface.sh
```

Para comprobar deliberadamente el modo autónomo aunque exista un host:

```bash
./setup/install-notifications-interface.sh --standalone
```

Este modo está pensado para ejecutar Notificaciones por sí sola. Si se mantienen
ambos frontends encendidos simultáneamente, deben configurarse `APP_PORT` y
`VITE_PORT` distintos para evitar publicar dos veces los mismos puertos.

En ambos modos se compilan `auth_v1.proto` y `notificaciones_v1.proto`. La
pantalla de acceso está en `/academico/login` y el flujo funcional queda en
`/academico/notificaciones`. No se agregan clientes de los demás dominios.

## Ejecutar y comprobar

El propio instalador levanta o reutiliza el Compose correcto y muestra las
rutas académicas. En modo adjunto, todas las operaciones Docker posteriores se
ejecutan desde el directorio de Login; no debe levantarse el Compose de una
segunda aplicación de Notificaciones.

El host predeterminado puede sustituirse con `GATEWAY_GRPC_HOST` en `.env`; si
el gateway usa TLS, definir `GATEWAY_GRPC_TLS=true`.
