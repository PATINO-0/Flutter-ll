# Demostración de Ritech: exportación de café

Alcance acordado el 9 de noviembre de 2026: solo café, Flutter y Supabase. Cacao, Django y Next.js no forman parte de esta entrega.

## Preparación y cuentas

Las cuentas DEMO y sus contraseñas están en `.demo/CUENTAS_LOCALES.md`, fuera de Git. No las copies al README ni a diapositivas. `.demo/state.json` conserva las claves generadas y el progreso del ensayo; no lo elimines si quieres reutilizar las cuentas. Los registros DEMO se conservan en Supabase para mostrarlos.

| Perfil | Cuenta preparada | Uso |
| --- | --- | --- |
| Administrador | Cuenta compartida por el equipo | Usuarios, roles, tarifas e indicadores generales. |
| Cliente | `ritech.demo.cliente.20261109@example.com` | Está como cliente, listo para iniciar un convenio desde la interfaz. |
| Asociado | `ritech.demo.asociado.20261109@example.com` | Tiene convenio aceptado, cultivo, lote de 100 kg y exportación entregada. |
| Trabajador | `ritech.demo.trabajador.20261109@example.com` | Revisa convenios/exportaciones y coordina transporte. Credencial comprobada. |
| Transportador | `ritech.demo.transportador.20261109@example.com` | Tiene la entrega histórica del ensayo; credencial comprobada. |

La cuenta `usuario@gmail.com` sí existe, pero actualmente tiene cliente y asociado: no sirve para demostrar una cuenta que aún no se ha vinculado. También existen trabajadores anteriores; se preparó un trabajador DEMO con contraseña conocida sin restablecer las claves de los demás.

Abre sesiones separadas (perfiles de navegador o ventanas privadas de navegadores distintos), para no cerrar la sesión del otro rol. No uses varias pestañas del mismo perfil para diferentes usuarios: comparten sesión.

Los seis soportes `DEMO_*.png` de `.demo/` son imágenes sintéticas del proyecto. Sirven para comprobar selección, carga, privacidad y conservación de documentos; no son documentos de identidad, facturas ni certificados comerciales válidos.

## Guion breve: 8–10 minutos

1. **Administrador, 1 minuto.** Abre Panel principal. Muestra lotes de café, clientes/asociados, solicitudes, exportaciones aceptadas y estados. Explica que aceptar una exportación y entregar el transporte son eventos distintos. Usa Actualizar indicadores después de cambios en otra sesión.
2. **Cliente, 1 minuto.** Entra con la cuenta DEMO cliente. Muestra Tienda y Solicitar convenio. Completa nombre DEMO, identificación ficticia `DEMO20261109`, teléfono `3000000000`, dirección sintética y actividad de exportación de café. Adjunta identidad, carta y certificado tributario DEMO. Marca tratamiento de datos y envía.
3. **Trabajador, 1 minuto.** Abre Solicitudes, ubica DEMO y revisa sus tres soportes. Prepara/aprueba la propuesta con vigencia. Muestra que esto aún no sustituye la aceptación del titular.
4. **Cliente, 1 minuto.** Actualiza su expediente y pulsa Aceptar mi convenio, con confirmación expresa. Comprueba que aparece el acceso de asociado. Nunca se acepta desde la sesión del trabajador.
5. **Asociado recién vinculado, 1 minuto.** En Café crea cultivo Caturra, Finca DEMO, ubicación sintética y 2,5 hectáreas. Crea lote con código nuevo `DEMO-PRESENTACION-01`, 100 kg y fecha de cosecha válida. Usa un código nuevo si ya hiciste este ensayo. Un lote aprobado no se reutiliza en otra exportación.
6. **Asociado, 1 minuto.** En Exportaciones solicita desde ese lote. Selecciona una ruta y tarifa activas del catálogo; escribe recogida, entrega, destinatario y teléfono DEMO. Muestra el cálculo peso × precio/kg y adjunta factura, empaque y calidad DEMO. Autoriza tratamiento e importe y envía. Es un registro de autorización; no se realiza un débito bancario.
7. **Trabajador, 1 minuto.** Abre Chat de Envíos/expediente, revisa documentos y aprueba. Muestra el seguimiento creado y el canal de coordinación. No envíes mensajes a clientes reales; cualquier mensaje del ensayo debe limitarse a cuentas DEMO.
8. **Transportador, 1 minuto.** Actualiza Envíos, identifica el código del lote DEMO y toma solo esa carga. Avanza Recibido → En camino (con ubicación ficticia) → Terminado/Entregado con anotación y confirmación de entrega. No tomes cargas de terceros.
9. **Asociado y administrador, 1 minuto.** Comprueba que la carga salió de Seguimiento activo y aparece en Mis envíos/historial. Abre el expediente y sus soportes. Actualiza indicadores y muestra el incremento en entregados.

El cliente DEMO cambia a asociado al completar el paso 4. Para una segunda exposición comienza desde ese estado o crea otra cuenta DEMO desde Administración; no intentes volverlo cliente borrando su historial.

## Recorrido de respaldo: 3 minutos

Si el tiempo es corto, usa el asociado DEMO ya preparado. Muestra convenio activo, cultivo y lote `DEMO-20261109`, exportación aceptada, documentos y entrega. Cambia al trabajador para supervisar y al transportador para mostrar el historial. El ensayo automático recorrió las operaciones reales con sesiones de cada rol y verificó persistencia y enlaces privados; no representa por sí solo un ensayo de todos los clics de la interfaz.

## Criterios de aceptación

- Personal: resumen global; asociado: únicamente sus datos y sin conteo de clientes.
- Solicitud con tres documentos y consentimiento; asociación solo después de aceptación del titular.
- Un lote se aprueba una vez; cotización persistida y autorización del titular.
- Conductor asignado registra recepción, ubicación y entrega confirmada.
- Entrega persistida, documentos todavía disponibles para el titular y retiro del seguimiento activo.
- Errores de consulta se muestran como errores, nunca como un cero ficticio.

## Reproducir la evidencia del backend

Desde la raíz ejecuta `node tool/rehearse_demo.mjs` con `RITECH_ADMIN_PASSWORD` definido en el proceso. El script no contiene esa contraseña, reutiliza las cuentas DEMO y omite los pasos que ya registró como completos. No crea otra entrega al repetirlo; para mostrar un proceso nuevo utiliza el guion en la interfaz con otro lote. El estado privado está en `.demo/state.json`; el resumen sin contraseñas está en `.demo/evidence.json`.

## Android

El AVD Pixel_9a buscaba la imagen en `C:\Android\Sdk`, donde no existe. La imagen está en el SDK de `%LOCALAPPDATA%\Android\Sdk`; Flutter quedó configurado con ese SDK. Se arrancó el emulador con renderizado por software y se comprobó `sys.boot_completed=1`.

Para abrirlo con ventana, cierra primero la instancia de ese mismo AVD que ya esté ejecutándose y utiliza Android Studio Device Manager. No borres ni restablezcas el AVD. Para compilar usa `flutter build apk --debug --no-pub`; para ejecutar, `flutter run -d emulator-5554 --no-pub` (verifica antes el identificador con `flutter devices`).

Gradle se ajustó a 8.14, como en el repositorio remoto y compatible con AGP 8.11.1. La configuración local anterior se respaldó en `.demo/gradle-wrapper.before.properties`. La licencia pendiente detectada corresponde a microXR, un complemento ajeno al Pixel y a esta aplicación; no bloquea la ejecución del emulador Android usado aquí.

## Resultado final de esta sesión

El APK debug compiló, se instaló en Pixel_9a e inicializó Supabase; se comprobó visualmente el formulario de acceso. Se redujo la resolución del emulador a 540×1212 y densidad 210 para evitar la saturación de System UI con renderizado por software. La compilación web actualizada se sirve en http://localhost:7360; se verificó el acceso administrativo y sus indicadores reales: 2 lotes, 3 clientes/asociados, 2 solicitudes aceptadas y 1 entrega terminada al momento del ensayo. Los totales cambian al agregar datos. El analizador final no reportó problemas y pasaron 63 pruebas Flutter, 34 de PostgreSQL/PGlite y 28 de funciones Deno (125 en total). El arreglo del chat también fue confirmado por el usuario en su teléfono físico. La [verificación final](verification_20261109.md) detalla el alcance y las limitaciones.

APK: build/app/outputs/flutter-apk/app-debug.apk. Evidencia local Android: .demo/android-login.png. El emulador del ensayo se inició sin ventana; para exponer la interfaz móvil puedes instalar el APK en tu teléfono o abrir el AVD en Android Studio tras cerrar la instancia de prueba.
