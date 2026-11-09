# Verificación de entrega — 9 de noviembre de 2026

Alcance: MVP de exportación de café con Flutter y Supabase. Esta revisión valida los cambios de indicadores, permisos del dashboard y actualización del chat, además de ejecutar todas las suites existentes.

## Pruebas automatizadas

| Comprobación | Resultado |
| --- | --- |
| `flutter test --no-pub` | 63 aprobadas, 0 fallidas |
| `npm.cmd test --prefix supabase/tests` | 34 aprobadas, 0 fallidas |
| `npm.cmd exec --yes --package=deno -- deno test --allow-env supabase/functions` | 28 aprobadas, 0 fallidas |
| `flutter analyze --no-pub` | Sin problemas |
| Inventario de documentación | 83 clases y enumeraciones verificadas |
| `node --check tool/rehearse_demo.mjs` | Correcto |
| `git diff --check` | Sin errores de espacios |

Total: **125 pruebas aprobadas**. Las pruebas PostgreSQL usan PGlite con Auth y Storage simulados; las pruebas de funciones usan dependencias controladas. No sustituyen todas las condiciones del servicio alojado.

El inventario de documentación se comprobó con una ejecución Node equivalente a `tool/verify_documentation.py`, porque Python no está instalado en este equipo.

## Comprobaciones contra el servicio real

- Se repitió el acceso con las cuatro cuentas DEMO existentes y se verificaron sus roles: cliente, asociado, trabajador y transportador.
- Se consultaron envíos bajo cada sesión y lotes bajo las sesiones autorizadas de asociado y trabajador.
- La entrega DEMO del ensayo previo continúa en estado `delivered`, con fecha de entrega persistida.
- Sus tres documentos de exportación siguen disponibles mediante enlaces privados: se comprobaron firma y descarga.
- Esta revisión final no creó cuentas ni envíos, no cambió roles y no envió mensajes.
- El ensayo previo cliente → convenio → asociado → lote → exportación con documentos → aprobación → transporte → entrega está documentado en [demo_backend_evidence.json](demo_backend_evidence.json).

## Regresión del chat

El envío podía guardarse correctamente y mostrar una advertencia falsa porque la función entregada a `setState` devolvía el `Future` de la recarga. Se cambió a una función síncrona sin valor de retorno. Las pruebas cubren envío confirmado sin duplicados, actualización manual, sondeo y conservación del borrador ante un rechazo real. El usuario confirmó el funcionamiento en su teléfono físico con la aplicación corregida.

## APK de entrega

`flutter build apk --release --no-pub` terminó correctamente. El APK de 56,5 MB está en `build/app/outputs/flutter-apk/app-release.apk`. Se instaló en el emulador Pixel_9a y se verificó el arranque hasta el formulario de acceso. El intento automatizado de escribir credenciales en ese emulador no introdujo correctamente el correo; no se considera una prueba de inicio de sesión aprobada en release. La autenticación real por rol se comprobó directamente contra Supabase y el chat corregido se confirmó previamente en el teléfono con debug.

SHA-256 del APK: `EEA21C1C4EB2E3DF9C295F1861D45A6319F379EA892FAA0C669AAF048C6A8E93`.

La compilación informó avisos de compatibilidad futura de Gradle 8.14, AGP 8.11.1 y Kotlin 2.2.20, además de un aviso de fuente Cupertino; no se encontró uso de `CupertinoIcons` en el código de la aplicación. El análisis Android de release terminó sin problemas. No se cambió la cadena de compilación durante la preparación de la entrega. El APK conserva la firma de desarrollo del proyecto: está preparado para instalación directa, no para publicación en una tienda.

## Alcance de la evidencia

`flutter build web --release --no-pub` también terminó correctamente, incluida su comprobación de compatibilidad Wasm. Se abrió la compilación actualizada en el navegador local con la sesión administrativa existente: el dashboard mostró 3 lotes, 3 clientes/asociados, 3 solicitudes (1 pendiente y 2 aceptadas), 1 transporte recibido y 1 entregado. Los totales reflejan el momento de la consulta y pueden cambiar. Los archivos web están en `build/web/`; no se publicó un nuevo sitio externo.

No se afirma ausencia absoluta de errores. No se repitió manualmente cada pantalla en todos los dispositivos ni se hicieron pruebas de carga o concurrencia de producción. El envío de correos, GPS automático, cobros bancarios y publicación en tiendas no forman parte de esta verificación. Los documentos DEMO son sintéticos.

El informe Word y los ajustes locales de VS Code se excluyen de la publicación por indicación del propietario. `.env` y `.demo/` permanecen fuera de Git; `.env.example` contiene solo los nombres de las variables.
