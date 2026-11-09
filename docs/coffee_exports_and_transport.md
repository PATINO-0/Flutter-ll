# Exportación de café y transporte

## Roles y propiedad

El orden efectivo es **Administrador > Trabajador > Transportador > Asociado > Cliente**. Los roles inferiores se conservan, pero la navegación y los permisos operativos corresponden al mayor. Transportador tiene un panel especializado: no recibe los permisos generales de trabajador.

| Rol efectivo | Acceso |
| --- | --- |
| Cliente | Tienda, vinculación y atención propia. |
| Asociado | Tienda de tarifas y destinos; sus cultivos, lotes, convenios, solicitudes, documentos, envíos, seguimiento y chats. |
| Transportador | Cargas disponibles, sus cargas asignadas, actualización de sus entregas y conversaciones de transporte. |
| Trabajador | Consulta todos los cultivos y titulares sin modificarlos; gestiona clientes y convenios, revisa exportaciones y coordina transportadores. |
| Administrador | Todos los módulos, administración de usuarios, tarifa por peso y operación de transporte. |

Las restricciones también se aplican en PostgreSQL y Storage. El transportador no puede consultar documentos de exportación ni cargos. Recibe el contacto del destinatario cuando toma la carga. Los lotes antiguos sin propietario o cultivo se muestran al personal para asignarlos explícitamente; no se atribuyen a un asociado por suposición.

## Cultivos, lotes y solicitud

En **Café**, el asociado con convenio activo registra nombre del cultivo, finca, ubicación, variedad y área. Registra después sus lotes con código, nombre, origen, peso, fecha de cosecha y observaciones. El trabajador supervisa el inventario con nombre y correo de su titular, sin registrar, modificar ni retirar cultivos o lotes. Administración conserva las acciones de corrección y asignación.

Las solicitudes se crean únicamente desde **Exportaciones → Solicitar exportación**, seleccionando un lote propio. El servidor reserva el lote: no permite otra solicitud en borrador, pendiente o aprobada sobre el mismo lote. Una exportación aprobada reserva definitivamente ese lote, incluso después de la entrega. No se permite editar o retirar un lote reservado.

La solicitud permite elegir **origen habilitado**, **destino conectado a ese origen** y **tarifa de la ruta**, utilizando el catálogo de la tienda. Reúne además las direcciones concretas de recogida y entrega en esos lugares, destinatario y teléfono, junto con tres documentos:

1. Factura comercial.
2. Lista de empaque.
3. Registro de calidad del café.

Son soportes propuestos para este flujo de Ritech; los requisitos definitivos dependen de la operación comercial. Se admiten PDF, JPG y PNG de hasta 10 MB. Se comprueba el contenido del archivo y su existencia en Storage. Los documentos son privados, no se sobrescriben y los enlaces autorizados duran un minuto.

El rechazo exige un motivo, que se comunica en el chat. El asociado puede corregir inmediatamente el mismo lote, sin esperar 30 días: ese plazo pertenece al convenio de vinculación. El nuevo borrador recupera los documentos y datos del intento rechazado y permite corregirlos. El intento anterior permanece en el historial.

## Cargo y autorización

El servidor calcula **peso del lote × tarifa por kilogramo de la ruta seleccionada**, con dos decimales y la moneda registrada en la tienda. La configuración global anterior de COP 1.200/kg queda como dato histórico y ya no se utiliza para cotizar solicitudes nuevas.

El administrador crea o edita cada servicio desde **Tienda → Crear tarifa / Editar tarifa**, registra origen, destino, importe, moneda y condiciones, utiliza unidad **kg**, y activa **Habilitar para exportación de café** y **Tarifa activa en la tienda y solicitudes**. Solo estas tarifas aparecen en las solicitudes. Las tarifas por volumen o destinadas únicamente a importación siguen en el catálogo sin ofrecerse para exportar café. No se habilitan automáticamente los ejemplos anteriores de importación ni se inventan destinos. Si no existen rutas válidas, el formulario informa al asociado y bloquea el envío.

El formulario muestra ruta, condiciones, peso, tarifa, moneda y total. Las casillas de autorización del cargo y tratamiento de datos comienzan desmarcadas. Solo el titular del lote puede autorizar y enviar la solicitud; un empleado no puede aceptar un cargo en nombre del asociado. Se guardan cuenta, fecha, versión del consentimiento y valores autorizados. Cambiar origen, destino o servicio elimina la autorización económica anterior. Si cambia la cotización o ruta antes del envío, se requiere actualizarla y volver a autorizar; una tarifa desactivada no permite enviar. El servidor obtiene los puntos de origen y destino del catálogo y los combina con las direcciones indicadas. No acepta orígenes ni destinos arbitrarios como sustitutos de los registrados.

La solicitud enviada conserva una copia de la ruta, condiciones y tarifa autorizadas. Un cambio o desactivación posterior en la tienda no altera el expediente ni recalcula el importe al aprobarlo. Los expedientes enviados antes de esta actualización mantienen su autorización histórica; los nuevos envíos de borradores o reintentos requieren seleccionar una tarifa habilitada.

La aprobación registra un cargo con estado `authorized` dentro de Ritech. **No existe débito bancario ni pago procesado por una pasarela.** La aplicación no muestra ese cargo como pagado.

## Revisión, archivo y chats

El envío de la solicitud crea una conversación en **Chat de Envíos**, independiente de **Chat de atención**. El trabajador abre el expediente desde la conversación y acepta o rechaza con correcciones. La aprobación crea el envío y su primer evento en una transacción; conserva la fotografía de los datos del lote, los documentos y el importe autorizado.

**Exportaciones aceptadas** conserva el archivo completo, tanto durante el transporte como después de entregar. El asociado ve sus expedientes; el personal ve todos. Los mensajes de la conversación de envío no incluyen el importe privado, porque el transportador asignado también participa en esa conversación operativa.

Desde **Transportadores**, el personal consulta disponibilidad, abre un chat directo y solicita recoger un envío. El mensaje no asigna la carga: el transportador debe tomarla desde **Envíos**. Los contadores distinguen atención, exportaciones y transporte.

## Transporte y entrega

El transportador toma una carga disponible. Puede añadir más lotes únicamente si coinciden la dirección completa de recogida y el destino de su ruta activa, ignorando mayúsculas y espacios repetidos. No puede tomar otra ruta ni añadir cargas una vez iniciado el trayecto. Las asignaciones se serializan y cada envío solo admite un transportador.

El flujo es **Aceptado → Recibido → En camino → Entregado**. Tomar una carga conserva el estado Aceptado y registra quién la tomó. Cada actualización exige una anotación. En camino exige también ubicación y permite actualizaciones sucesivas; los eventos y avisos aparecen en el chat del envío. Solo el transportador asignado o el administrador pueden actualizarlo. El trabajador coordina y revisa, pero no suplanta al conductor.

Para terminar se exige marcar la confirmación de entrega. El asociado recibe el aviso en el chat. **Seguimiento** muestra únicamente envíos activos; **Mis envíos** conserva únicamente las entregas realizadas y su destino. Ninguna de esas dos pantallas crea solicitudes.

Los chats y las cargas del transportador se actualizan cada cinco segundos mientras están abiertos. El dashboard comprueba roles y avisos cada quince segundos. Son notificaciones internas; no se implementan notificaciones push en segundo plano ni localización GPS automática.

Las comprobaciones periódicas del perfil no vuelven a consultar todos los módulos: las listas dependen únicamente de la cuenta, su estado activo y el rol efectivo. Mientras no cambien esos permisos, se conservan las tarjetas desplegadas, el menú, los formularios y las selecciones abiertas. Los sondeos esperan a que termine una consulta pendiente para no reiniciarla continuamente en conexiones lentas. Un cambio real de permisos vuelve a cargar los datos autorizados; la desactivación sigue bloqueando el panel.

Exportaciones y Seguimiento/Mis envíos actualizan su propia lista cada quince segundos cuando la ruta está visible, conservando los datos durante la consulta. No ejecutan ese sondeo mientras hay un formulario o diálogo abierto encima. El seguimiento identifica cada tarjeta por el envío para mantener su expansión aunque llegue otro registro a la lista.

## Activar en Supabase

Desde la raíz del repositorio:

```powershell
npx supabase@3.0.0 login
npx supabase@3.0.0 link --project-ref mdlcewexhzskapxiklsm
npx supabase@3.0.0 db push --remote --dry-run
npx supabase@3.0.0 db push --remote --yes
npx supabase@3.0.0 functions deploy create-user manage-user seed-transporters --use-api --yes
```

Se mantienen las cuatro migraciones iniciales y se añaden, en orden:

5. `20261108040000_coffee_export_requests.sql`: transportador, propiedad de cultivos y lotes, expedientes, documentos, tarifa y cargos.
6. `20261108050000_export_dispatch_and_channels.sql`: autorización del titular, revisión, canales, asignación de cargas y entrega.
7. `20261108060000_export_freight_routes.sql`: tarifas y rutas habilitadas de la tienda, validación de la cotización y conservación de sus condiciones.
8. `20261109000000_agreement_lifecycle.sql`: propuesta, aceptación, vigencia y revocación de convenios.
9. `20261109010000_coffee_supervision.sql`: supervisión de Café, identidad de titulares y convenio activo para nuevas exportaciones.

El CLI aplica únicamente las migraciones pendientes. Si el esquema anterior se aplicó manualmente, verifica y sincroniza primero su historial. Si ya están instaladas las siete migraciones iniciales, aplica solamente la octava y novena. No repitas la creación del esquema sobre tablas existentes. `build/final_mvp_update.sql` agrupa las dos migraciones finales; `build/coffee_exports_and_transport_update.sql` corresponde a la fase anterior de exportaciones y no debe repetirse sobre un proyecto que ya la tenga instalada.

Las tres funciones de servidor validan la sesión y administración internamente, aunque la configuración del gateway use `verify_jwt = false`. La clave administrativa permanece en el servidor.

## Crear las cinco cuentas de prueba

Después del despliegue, inicia sesión con el administrador y abre **Transportadores → Crear cinco transportadores de prueba**. Se crean exactamente estas cinco cuentas con rol `transporter` y contraseña inicial `12345678`:

- `transportador@gmail.com`
- `transportador1@gmail.com`
- `transportador2@gmail.com`
- `transportador3@gmail.com`
- `transportador4@gmail.com`

La operación requiere administración vigente. Repetirla omite transportadores existentes sin cambiar su contraseña. Si una dirección pertenece a otra clase de usuario o está desactivada, informa el conflicto sin modificarla. Los errores se muestran por cuenta y las demás pueden completarse. Son credenciales de prueba solicitadas para este entorno.

Los archivos locales no crean usuarios ni aplican migraciones por sí solos. La creación efectiva sucede al ejecutar el botón después del despliegue. Desplegar únicamente `seed-transporters` no habilita la creación o edición general: también deben estar desplegadas `create-user` y `manage-user`, como indica el comando de instalación anterior. La [guía de registro y roles](registration_and_roles.md) explica cómo identificar una función ausente cuando el navegador informa de CORS.

## Verificación

```powershell
flutter analyze --no-pub
flutter test --no-pub
npm ci --prefix supabase/tests
npm test --prefix supabase/tests
npm exec --yes --package=deno -- deno test --allow-env supabase/functions
flutter build apk --debug --no-pub
flutter build web --no-pub
```

Las pruebas comprueban aislamiento por propietario, permisos, reservas y reintentos, documentos, cotización y autorización, aprobación, cargas compatibles, transiciones, confirmación de entrega, canales y creación idempotente de cuentas. PostgreSQL en memoria simula Auth y Storage; Flutter sustituye repositorios y las funciones sustituyen la red. Después del despliegue queda comprobar el flujo con sesiones y archivos reales y la concurrencia con varias conexiones.
