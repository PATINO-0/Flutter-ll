import 'package:flutter/material.dart'; // Construye la bienvenida personalizada.

import '../../../auth/domain/entities/user_profile.dart'; // Proporciona el nombre y los roles asignados.

/// Explica las funciones disponibles de acuerdo con los roles actuales del usuario.
class DashboardHome extends StatelessWidget {
  const DashboardHome({required this.profile, super.key});

  final UserProfile profile; // Recibe el perfil cargado desde el servidor.

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(
      context,
    ); // Utiliza los estilos definidos por la aplicación.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(
        24,
      ), // Permite leer el panel en dispositivos pequeños.
      child: Align(
        alignment: Alignment
            .topCenter, // Mantiene el contenido centrado horizontalmente.
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1000,
          ), // Limita el ancho de lectura.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment
                .start, // Alinea la bienvenida y los permisos.
            children: [
              Text('Panel principal', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8), // Separa el título del saludo.
              Text(
                'Bienvenido, ${profile.fullName}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(
                height: 24,
              ), // Separa el saludo de la información de acceso.
              Text('Tus roles en Ritech', style: theme.textTheme.titleLarge),
              Text(
                'Acceso actual: ${profile.effectiveRole?.label ?? 'Sin rol asignado'}',
              ), // Explica qué nivel predomina cuando existen varios roles.
              const SizedBox(height: 12), // Separa el encabezado de los roles.
              if (profile.roles.isEmpty)
                const Text(
                  'Todavía no tienes roles asignados. Contacta al administrador para solicitar acceso a los módulos.',
                ),
              for (final role in profile.roles)
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.verified_user_outlined,
                    ), // Identifica un permiso concedido por el servidor.
                    title: Text(
                      role.label,
                    ), // Muestra el nombre del rol en español.
                    subtitle: Text(
                      role.description,
                    ), // Explica sus responsabilidades dentro de Ritech.
                  ),
                ),
              const SizedBox(
                height: 24,
              ), // Separa los permisos de las instrucciones.
              const Text(
                'Utiliza el menú para consultar tus operaciones, convenios y mensajes de atención.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
