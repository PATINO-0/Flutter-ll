# Registro de usuarios y administración de roles

La aplicación permite el registro público de clientes y ofrece un panel adicional a los administradores. Una cuenta puede tener varios roles; al retirarlos todos conserva únicamente su panel principal.

## Alcance de los roles

| Rol | Identificador | Navegación habilitada |
| --- | --- | --- |
| Administrador | `admin` | Administración de usuarios y acceso a los módulos del sistema. |
| Cliente | `client` | Tienda, solicitud de vinculación y atención propia. |
| Asociado | `associate` | Tienda de tarifas y destinos; sus cultivos, lotes, convenios, envíos, exportaciones, seguimiento y atención propia. |
| Trabajador | `worker` | Café, clientes, solicitudes, convenios, exportaciones, seguimiento y atención. |
| Transportador | `transporter` | Cargas disponibles, sus envíos asignados, actualización de entregas y chat de transporte. |

Funcionan el registro, la administración de cuentas y roles y el flujo de tienda, convenios, chat y operaciones. Predomina Administrador > Trabajador > Transportador > Asociado > Cliente. La [guía de convenios y atención](association_workflow.md) describe la vinculación y la [guía de exportaciones y transporte](coffee_exports_and_transport.md) detalla el flujo de café, cargos y entregas.

## Aplicar los cambios en Supabase

Los archivos del repositorio preparan el backend, pero no modifican por sí solos el proyecto remoto. Ejecuta los comandos desde la raíz de `Flutter-ll` con acceso al proyecto correspondiente:

```powershell
npx supabase@3.0.0 login
npx supabase@3.0.0 link --project-ref mdlcewexhzskapxiklsm
npx supabase@3.0.0 db push --remote --dry-run
npx supabase@3.0.0 db push --remote --yes
npx supabase@3.0.0 functions deploy create-user manage-user seed-transporters --use-api --yes
```

Las migraciones deben aplicarse en este orden:

1. `supabase/migrations/20261108000000_registration_and_roles.sql`: crea los roles y asigna cliente a las cuentas existentes y futuras.
2. `supabase/migrations/20261108010000_assign_test_administrator.sql`: asigna administración a la cuenta de prueba indicada por el propietario y actualiza el esquema publicado.
3. `supabase/migrations/20261108020000_association_workflow.sql`: incorpora estado activo, tienda, solicitudes, documentos privados, convenios y chat.
4. `supabase/migrations/20261108030000_commercial_operations.sql`: incorpora envíos, historial de seguimiento y gestión de café.
5. `supabase/migrations/20261108040000_coffee_export_requests.sql`: incorpora transportador, cultivos y lotes propios, solicitudes, documentos, tarifa y cargos.
6. `supabase/migrations/20261108050000_export_dispatch_and_channels.sql`: incorpora autorización del titular, revisión, canales, asignaciones y entrega.
7. `supabase/migrations/20261108060000_export_freight_routes.sql`: utiliza las rutas y tarifas habilitadas de la tienda al cotizar y enviar, y conserva sus condiciones autorizadas.
8. `supabase/migrations/20261109000000_agreement_lifecycle.sql`: incorpora propuesta, aceptación expresa del titular, vigencia, exclusión de duplicados y revocación con motivo y aviso.
9. `supabase/migrations/20261109010000_coffee_supervision.sql`: restringe escritura de cultivos a asociado titular con convenio activo y administración, y permite al trabajador consultar sus titulares.

También pueden ejecutarse completas desde el editor SQL del proyecto si el esquema anterior se administraba manualmente. La primera se ejecuta una sola vez; la segunda admite ejecuciones repetidas. No combines el editor SQL y el CLI sin sincronizar el historial de migraciones.

La migración conserva los perfiles existentes y reemplaza sus políticas de acceso para que cada usuario lea únicamente su perfil, mientras el administrador consulta todos. El registro crea el perfil y el rol de cliente dentro de la misma transacción de autenticación. La función habitual `public.handle_new_user` se actualiza para admitir ejecuciones repetidas; si el proyecto tiene otros disparadores personalizados de registro que escriben perfiles, revisa su compatibilidad antes del despliegue.

La función `create-user` utiliza las variables de servidor `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY`, disponibles en el entorno alojado de Supabase. La clave administrativa permanece en el servidor. El archivo `.env` de Flutter solo necesita `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`.

La configuración `verify_jwt = false` desactiva la validación antigua del gateway para esta función. La implementación exige un token Bearer, lo valida con `auth.getUser` y consulta el rol administrativo antes de utilizar la API de administración. La asignación final vuelve a comprobar los permisos en PostgreSQL.

## Administrador inicial

La cuenta de prueba autorizada es `usuarioprueba@gmail.com`, con UUID `1bb00d6c-9b14-43d0-b096-88969fcd8376`. La segunda migración exige que coincidan ambos datos antes de asignar `admin`, incluso cuando ya existen clientes nuevos.

La primera migración también conserva el comportamiento inicial para proyectos con una única cuenta previa: esa cuenta recibe `admin` además de `client`. Ningún registro posterior se convierte automáticamente en administrador, incluso si el proyecto estaba vacío al desplegar. La aplicación nunca asigna administración a partir del correo ni de los metadatos: consulta los roles de Supabase.

Si existen varias cuentas, un operador debe seleccionar la cuenta responsable en el editor SQL de Supabase. Sustituye el UUID del ejemplo por el identificador verificado de la cuenta:

```sql
-- Asigna administración únicamente a la cuenta elegida por el operador del proyecto.
insert into public.user_roles (user_id, role)
values ('UUID-DE-LA-CUENTA-EXISTENTE'::uuid, 'admin')
on conflict do nothing;
```

## Corrección de la carga del dashboard

Se verificó que el proyecto remoto respondía `PGRST205` al consultar `public.user_roles`: la tabla todavía no estaba disponible en el esquema publicado. La consulta anterior unía esa tabla al perfil, por lo que el fallo de roles impedía cargar todos los datos del usuario.

La aplicación ahora consulta primero el perfil y después los roles, sin depender de una relación entre tablas. Cuando la tabla de roles todavía no existe, permite abrir el dashboard con la navegación básica de cliente. Una lista vacía de roles del servidor sigue significando que el usuario no tiene roles; no se reemplaza automáticamente por cliente. Los errores de permisos o de conexión tampoco se convierten en roles válidos.

Si una cuenta autenticada todavía no tiene perfil, la aplicación utiliza exclusivamente sus propios datos de Supabase Auth y le permite mostrar el panel de cliente. Esto no crea filas ni permisos en la base de datos; las migraciones siguen siendo necesarias para persistir el perfil y los roles. La carga completa tiene un límite de diez segundos y ofrece un mensaje recuperable cuando se supera. Los perfiles antiguos con `updated_at` nulo utilizan su fecha de creación.

La corrección local permite entrar al dashboard antes de completar el despliegue, pero el acceso administrativo y las operaciones protegidas requieren las tablas, funciones y políticas del servidor. No añadas claves administrativas a Flutter ni concedas lectura pública de perfiles para resolver este problema.

## Confirmación del correo

Habilita el registro por correo y contraseña en Supabase Auth. La aplicación respeta la opción de confirmación: si Supabase devuelve una sesión, abre el panel; si no devuelve sesión, solicita revisar el correo y regresar para iniciar sesión.

Configura en Supabase Auth una dirección HTTPS válida para `Site URL` y las redirecciones permitidas del correo. La confirmación puede completarse en el navegador y después el cliente puede volver manualmente a la aplicación móvil e iniciar sesión. Esta entrega no incorpora enlaces profundos nativos. Configura también los requisitos de contraseña del proyecto; la interfaz exige entre 8 y 72 caracteres y presenta el rechazo si el servidor aplica reglas adicionales.

El mensaje de confirmación no revela si una dirección ya estaba registrada cuando Supabase protege esa información. El formulario público no envía roles. El disparador ignora permisos incluidos por un cliente en sus metadatos.

## Crear cuentas y modificar roles

El administrador abre **Administración de usuarios**, consulta las cuentas por páginas y utiliza **Crear usuario** o **Editar roles**. La creación administrativa solicita nombre, correo, contraseña y al menos un rol. La cuenta queda habilitada directamente por el administrador; esta operación no envía correos de confirmación ni comparte la contraseña automáticamente. El administrador debe comunicar las credenciales por un canal privado.

La creación utiliza la API administrativa del servidor y conserva la sesión actual. Si falla la asignación de roles, intenta eliminar la cuenta recién creada. Si esa reversión también falla, devuelve un aviso explícito para revisar la cuenta y sus permisos. La creación de Auth y la asignación de roles son operaciones de servicios distintos y no forman una transacción distribuida.

La edición sustituye todos los roles en una transacción de PostgreSQL. Un bloqueo transaccional serializa estas modificaciones y evita que dos cambios de roles retiren simultáneamente a los últimos administradores. Las restricciones se aplican también al editar la propia cuenta.

La aplicación vuelve a cargar el perfil cuando cambia la sesión, al regresar desde administración, al volver del segundo plano o al pulsar actualizar. Las operaciones administrativas verifican los roles actuales en el servidor, por lo que una revocación no requiere renovar el token para impedir nuevas operaciones.

## Error de CORS al actualizar un usuario

Si el navegador indica que la petición previa no tiene un estado HTTP correcto, comprueba primero la respuesta de `OPTIONS` a `/functions/v1/manage-user`. Un `404` con `Requested function was not found` indica que falta desplegar esa función; no se corrige modificando los roles del administrador ni las políticas de lectura.

Desplegar únicamente `seed-transporters` crea el servicio de cuentas de prueba, pero no instala los servicios de creación ni edición de usuarios. Desde la raíz del proyecto, ejecuta:

```powershell
npx supabase@3.0.0 functions deploy create-user manage-user --project-ref mdlcewexhzskapxiklsm --use-api --yes
```

Después, `OPTIONS` debe devolver un estado correcto y permitir las cabeceras `authorization`, `apikey`, `x-client-info` y `content-type`. Un `POST` sin sesión debe seguir devolviendo `401`; admitir CORS no concede administración. Recarga la aplicación y prueba la edición con una sesión administrativa vigente. Los tests de funciones comprueban ambas condiciones sin crear ni modificar cuentas reales.

## Validación local

```powershell
flutter analyze
flutter test
flutter build apk --debug
flutter build web
npm ci --prefix supabase/tests
npm test --prefix supabase/tests
npm exec --yes --package=deno -- deno check supabase/functions/create-user/index.ts
npm exec --yes --package=deno -- deno test --allow-env supabase/functions/create-user/index_test.ts
```

Las pruebas de Flutter sustituyen los repositorios para comprobar registro, confirmación, navegación y edición de roles sin crear cuentas reales. Las pruebas SQL ejecutan la migración en PostgreSQL en memoria mediante PGlite y simulan únicamente el esquema de Supabase Auth. Comprueban disparadores, privilegios, políticas de lectura, permisos administrativos y la protección del último administrador. Las pruebas de la función sustituyen las respuestas de red para comprobar autenticación, autorización, validación y reversión. No sustituyen la validación final contra el proyecto real, el proveedor de correo ni una prueba de concurrencia con varias conexiones.

## Referencias de Supabase

- [Registro con Flutter y comportamiento de la confirmación](https://supabase.com/docs/reference/dart/auth-signup).
- [Administración de usuarios desde el servidor](https://supabase.com/docs/reference/javascript/auth-admin-createuser).
- [Integración de sesiones en funciones de servidor](https://supabase.com/docs/guides/functions/auth-legacy-jwt).
- [Políticas de seguridad por fila](https://supabase.com/docs/guides/database/postgres/row-level-security).
