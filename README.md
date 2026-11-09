# Ritech

Aplicación móvil modular construida con Flutter, Riverpod y Supabase para clientes, asociados y personal de Ritech.

Incluye registro público de clientes y administración de usuarios con roles múltiples. El código utiliza identificadores en inglés y comentarios y textos de interfaz en español.

Incluye tienda, solicitudes de convenio con documentos privados y consentimiento, aprobación por trabajadores, promoción a asociado, chat interno, envíos, seguimiento y gestión de café. Consulta la [guía de convenios y atención](docs/association_workflow.md) para revisar permisos, reglas y desplegar el backend actualizado.

El flujo de exportación de café incorpora cultivos y lotes propios, selección de rutas y tarifas habilitadas en la tienda, documentos y cargo autorizado por peso, revisión por empleados, chat de envíos y entrega por transportadores. Consulta la [guía de exportaciones y transporte](docs/coffee_exports_and_transport.md) para activar las migraciones y crear las cinco cuentas de transporte de prueba. El cargo se registra en Ritech; no procesa débitos bancarios.

Consulta la [guía de registro y roles](docs/registration_and_roles.md) para aplicar la migración, desplegar la función de creación de usuarios, preparar al administrador inicial y ejecutar las pruebas. Estos pasos de Supabase son necesarios antes de utilizar la nueva funcionalidad contra el proyecto remoto.

Integrantes: Vanessa Bastidas, Samuel Patiño, Juan Vizuette y Anderson Ojeda.
