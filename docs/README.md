# Interfaces plugables por core asset

Cada módulo puede crear una aplicación Livewire independiente o agregarse a un
host ya preparado. El instalador genera la estructura común con Artisan,
compila los clientes con `protoc` y mantiene un registro acumulativo de módulos.

| Core asset | Receta independiente | Ruta funcional |
|---|---|---|
| Autenticación y sesiones | [academico-login.md](academico-login.md) | `/academico/sesiones` |
| Gestión de usuarios | [academico-usuarios.md](academico-usuarios.md) | `/academico/usuarios` |
| Matrículas | [academico-matriculas.md](academico-matriculas.md) | `/academico/matriculas` |
| Calificaciones | [academico-calificaciones.md](academico-calificaciones.md) | `/academico/calificaciones` |
| Solicitudes académicas | [academico-solicitudes.md](academico-solicitudes.md) | `/academico/solicitudes` |
| Notificaciones | [academico-notificaciones.md](academico-notificaciones.md) | `/academico/notificaciones` |

Las cinco interfaces funcionales utilizan además el contrato de
`academico-login` para iniciar y mantener una sesión segura. Esa es una
dependencia técnica; no instala la interfaz funcional de ningún otro core
asset. Los módulos agregados comparten Auth y la sesión, pero conservan sus
contratos, acciones y contexto bajo espacios de nombres separados.

Notificaciones ofrece el flujo automático de composición:

```bash
./setup/install-notifications-interface.sh --plan
./setup/install-notifications-interface.sh
```

Si existe un host Login, se agrega allí sin crear otro Compose; si no existe,
se crea una aplicación autónoma con su propio Login.

Para auditar una selección sin modificar archivos:

```bash
/home/azureuser/academico-scaffolding/setup/install-interface-module.sh \
  academico-notificaciones \
  /ruta/a/la/aplicacion \
  --plan
```
