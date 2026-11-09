# Tienda, convenios y atención de Ritech

## Permisos efectivos

Predomina el mayor nivel: **Administrador > Trabajador > Transportador > Asociado > Cliente**. Los roles asignados se conservan; la aprobación añade `associate` y su mayor nivel sustituye la navegación inicial de cliente. El transportador utiliza un panel limitado a sus cargas y chats, sin permisos generales de trabajador.

| Rol efectivo | Funciones |
| --- | --- |
| Cliente | Tienda de servicios, requisitos de vinculación, sus solicitudes y chat de atención. |
| Asociado | Tienda de tarifas y destinos; sus cultivos, lotes, convenios, envíos, exportaciones, seguimiento y chat. No consulta operaciones de otros asociados. |
| Transportador | Cargas disponibles, sus asignaciones, actualización de entregas y chat de transporte. |
| Trabajador | Clientes y asociados, solicitudes, convenios y sus documentos, operaciones, seguimiento, café y conversaciones de atención. |
| Administrador | Todos los módulos anteriores, precios de la tienda y administración de usuarios. |

Los clientes no registran importaciones ni consultan envíos antes de ser asociados. El control se aplica también en funciones y políticas de PostgreSQL, independientemente del menú de Flutter.

## Solicitud de convenio

El cliente pulsa **Quiero convertirme en asociado exportador**, completa nombre, identificación, teléfono, dirección y actividad comercial, y adjunta:

1. Documento de identidad legible.
2. Carta firmada de solicitud de convenio que describa su intención de vinculación.
3. Certificado tributario, como RUT o equivalente.

Se aceptan PDF, JPG y PNG de hasta 10 MB por archivo. La aplicación comprueba las cabeceras reales del archivo y el servidor verifica que los tres soportes existan en el depósito privado. Un borrador permite reemplazar referencias mediante cargas nuevas. Los soportes enviados permanecen inmutables desde el cliente y se conservan en el convenio aprobado.

El botón **Tratamiento de datos** presenta el aviso; la casilla de aceptación empieza desmarcada. El envío registra la fecha, versión y cuenta que consintió. Cuando un trabajador prepara la solicitud desde **Clientes** o **Crear convenio para un cliente**, confirma que dispone de la autorización correspondiente y queda identificado como responsable de la remisión.

Solo puede haber un borrador o solicitud pendiente por titular. Un borrador no consume el plazo. Al enviar se valida, con hora del servidor y bloqueo transaccional, que no exista otro envío durante los últimos 30 días. Si el último intento fue rechazado, se permite crear uno nuevo inmediatamente. El servidor vuelve a comprobar la regla al enviar, aunque el formulario se hubiera abierto antes.

## Revisión y chat

El envío crea o recupera el chat del cliente y publica una notificación de sistema. Cada trabajador o administrador dispone de su propio contador de mensajes sin leer. El cliente solo consulta su conversación.

La aprobación crea un convenio con consecutivo `RIT-000001`, conserva el expediente con sus documentos y añade el rol de asociado en una única transacción. El rechazo requiere un motivo de entre 5 y 2000 caracteres y lo entrega al cliente en el mismo chat. Una solicitud no puede resolverse dos veces.

El chat y la bandeja se actualizan cada cinco segundos mientras están abiertos. El dashboard actualiza roles y notificaciones cada quince segundos cuando la aplicación está activa. Las notificaciones de esta entrega son internas; no se envían notificaciones push al dispositivo en segundo plano. El historial permite cargar mensajes anteriores en bloques de cien.

## Administración de cuentas

El administrador puede corregir nombre, correo y roles. La función `manage-user` sincroniza Auth con el perfil y conserva la protección del último administrador. Si el servidor rechaza el cambio de permisos, intenta compensar los datos de Auth; un fallo de conexión entre ambos servicios requiere revisar el estado desde la lista de usuarios.

**Eliminar acceso** es una eliminación lógica: desactiva el perfil, retira los roles y bloquea nuevos accesos en Auth. Los convenios, documentos, solicitudes y mensajes permanecen como historial. Las políticas comprueban el estado activo en cada operación, de modo que un token anterior no permite seguir consultando esos datos. No se permite retirar al último administrador activo.

Los documentos usan URLs autorizadas de un minuto de duración. Una URL ya emitida o un archivo descargado no se recupera al revocar una cuenta; la revocación impide emitir nuevos enlaces y acceder a los servicios. Los archivos que un usuario reemplaza en un borrador conservan protección privada y requieren una limpieza administrativa posterior si no forman parte de un expediente enviado.

## Catálogo y operaciones

Las tres tarifas iniciales son **ejemplos ilustrativos**, no precios reales ni cotizaciones vigentes. El administrador puede crear tarifas, editar su precio y condiciones y desactivarlas desde la tienda. Sustituye estos valores por información comercial aprobada antes de ofrecer cotizaciones a clientes.

Las solicitudes se realizan desde Exportaciones y actualmente corresponden solo a café. Requieren un cultivo y lote propios, documentos y autorización del importe por peso. El trabajador revisa; el transportador asignado actualiza los estados y confirma la entrega. Café permite gestionar cultivos y lotes propios al asociado y todos los registros al personal. La [guía de exportaciones y transporte](coffee_exports_and_transport.md) describe las reglas actuales, los chats separados, el archivo documental y el despliegue adicional.

## Despliegue

Desde la raíz del repositorio, aplica las siete migraciones en orden y despliega las tres funciones. El CLI registra las migraciones ya aplicadas y solo ejecuta las pendientes:

```powershell
npx supabase@3.0.0 login
npx supabase@3.0.0 link --project-ref mdlcewexhzskapxiklsm
npx supabase@3.0.0 db push --remote --dry-run
npx supabase@3.0.0 db push --remote --yes
npx supabase@3.0.0 functions deploy create-user manage-user seed-transporters --use-api --yes
```

Si el esquema se aplicó manualmente desde el editor SQL, sincroniza primero su historial de migraciones; no vuelvas a ejecutar la primera migración sobre tablas que ya existen. Después de las migraciones de convenios y operaciones se aplican `20261108040000_coffee_export_requests.sql`, `20261108050000_export_dispatch_and_channels.sql` y `20261108060000_export_freight_routes.sql`.

El archivo de configuración mantiene `verify_jwt = false` para compatibilidad con las claves publicables. Las tres funciones validan el token con Supabase Auth y consultan administración antes de utilizar la clave de servidor. No copies la clave administrativa a Flutter. Los depósitos privados y sus políticas se crean mediante las migraciones.

## Verificación

```powershell
flutter analyze
flutter test
npm ci --prefix supabase/tests
npm test --prefix supabase/tests
npm exec --yes --package=deno -- deno test --allow-env supabase/functions
flutter build apk --debug
flutter build web
```

Las pruebas SQL utilizan PostgreSQL en memoria con interfaces simuladas de Auth y Storage. Las pruebas de funciones sustituyen la red y las de Flutter sustituyen repositorios para no crear cuentas ni enviar documentos reales. La validación final de correo, selección de archivos en dispositivos y despliegue debe completarse contra el proyecto alojado después de aplicar las migraciones.
