import 'package:flutter/material.dart'; // Construye el panel de administración.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Observa usuarios y permisos actuales.
import 'package:go_router/go_router.dart'; // Permite regresar al panel principal.

import '../../../../core/constants/app_routes.dart'; // Comparte las rutas del sistema.
import '../../../../core/errors/app_exception.dart'; // Identifica los errores que se pueden mostrar.
import '../../../auth/domain/entities/user_profile.dart'; // Representa la cuenta que se editará.
import '../../../auth/presentation/providers/auth_providers.dart'; // Consulta el perfil autenticado.
import '../../data/repositories/supabase_user_management_repository.dart'; // Comparte el tamaño de página.
import '../providers/administration_providers.dart'; // Carga la lista de forma protegida.
import '../widgets/user_editor_dialog.dart'; // Crea cuentas o modifica sus roles.

/// Presenta una lista paginada de cuentas exclusivamente a administradores.
class AdministrationPage extends ConsumerStatefulWidget {
  const AdministrationPage({super.key});

  @override
  ConsumerState<AdministrationPage> createState() => _AdministrationPageState();
}

/// Mantiene la página actual y coordina las actualizaciones del panel.
class _AdministrationPageState extends ConsumerState<AdministrationPage> {
  int _page = 0; // Empieza en la primera página de usuarios.

  /// Vuelve a consultar tanto los permisos como la lista de usuarios.
  void _refresh() {
    ref.invalidate(
      currentUserProfileProvider,
    ); // Detecta cambios en los roles de la sesión actual.
    ref.invalidate(
      adminUsersProvider,
    ); // Evita conservar páginas con permisos desactualizados.
  }

  /// Abre un único formulario y actualiza los datos cuando termina.
  Future<void> _editUser([UserProfile? profile]) async {
    final saved = await showDialog<bool>(
      context: context, // Utiliza el contexto del panel actual.
      barrierDismissible:
          false, // Requiere cancelar o completar la operación explícitamente.
      builder: (_) => UserEditorDialog(
        profile: profile,
      ), // Decide entre creación y edición.
    );
    if (!mounted) return; // Evita refrescar un panel que ya se cerró.
    _refresh(); // Comprueba también si el administrador retiró su propio rol.
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profile == null
                ? 'Usuario creado correctamente.'
                : 'Usuario actualizado correctamente.',
          ),
        ),
      );
    }
  }

  /// Confirma la revocación conservando el historial comercial del usuario.
  Future<void> _deleteUser(UserProfile user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar acceso del usuario'),
        content: Text(
          'Se retirará el acceso de ${user.fullName}. Sus solicitudes, mensajes y convenios se conservarán como historial. El último administrador no puede eliminarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar acceso'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(userManagementRepositoryProvider).deactivateUser(user.id);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El acceso del usuario fue eliminado.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is AppException
                  ? error.userMessage
                  : 'No fue posible eliminar el acceso.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(
      currentUserProfileProvider,
    ); // Observa los permisos vigentes.
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Administración de usuarios',
        ), // Identifica la función protegida.
        leading: IconButton(
          tooltip:
              'Volver al panel', // Describe la navegación para accesibilidad.
          icon: const Icon(Icons.arrow_back), // Representa el regreso al panel.
          onPressed: () => context.go(
            AppRoutes.dashboard,
          ), // Evita dejar el formulario como ruta inicial.
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar usuarios y permisos',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: profile.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ), // Espera la comprobación de permisos.
        error: (_, _) => Center(
          child: TextButton(
            onPressed: _refresh,
            child: const Text('No fue posible verificar tu acceso. Reintentar'),
          ),
        ),
        data: (currentProfile) {
          if (currentProfile?.isAdmin != true) {
            return const Center(
              child: Text('No tienes permiso para administrar usuarios.'),
            );
          }
          return _buildUsers(); // Muestra los datos únicamente al administrador.
        },
      ),
    );
  }

  /// Muestra estados de carga, errores y resultados de la página solicitada.
  Widget _buildUsers() {
    final users = ref.watch(
      adminUsersProvider(_page),
    ); // Consulta la página con validación del servidor.
    return users.when(
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ), // Indica que se consultan las cuentas.
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(
            24,
          ), // Evita que el aviso toque los bordes.
          child: Column(
            mainAxisSize: MainAxisSize
                .min, // Centra el aviso sin ocupar toda la pantalla.
            children: [
              Text(
                error is AppException
                    ? error.userMessage
                    : 'No fue posible cargar los usuarios.',
              ),
              TextButton(onPressed: _refresh, child: const Text('Reintentar')),
            ],
          ),
        ),
      ),
      data: (items) => ListView(
        padding: const EdgeInsets.all(
          20,
        ), // Deja espacio legible en pantallas móviles.
        children: [
          Align(
            alignment:
                Alignment.centerLeft, // Mantiene visible la acción principal.
            child: FilledButton.icon(
              onPressed: () => _editUser(),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Crear usuario'),
            ),
          ),
          const SizedBox(height: 16), // Separa el botón de la lista de cuentas.
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No hay más usuarios para mostrar.'),
            ),
          for (final user in items)
            Card(
              child: ListTile(
                isThreeLine:
                    true, // Reserva espacio para el nombre, correo y roles.
                title: Text(
                  user.fullName,
                ), // Identifica a la persona registrada.
                subtitle: Text(
                  '${user.email}\n${user.roles.isEmpty ? 'Sin roles asignados' : user.roles.map((role) => role.label).join(', ')}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar roles de ${user.fullName}',
                      onPressed: () => _editUser(user),
                      icon: const Icon(Icons.manage_accounts_outlined),
                    ),
                    IconButton(
                      tooltip: 'Eliminar acceso de ${user.fullName}',
                      onPressed: () => _deleteUser(user),
                      icon: const Icon(Icons.person_remove_outlined),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16), // Separa la paginación de los resultados.
          Wrap(
            spacing: 16, // Permite adaptar los controles a pantallas estrechas.
            crossAxisAlignment:
                WrapCrossAlignment.center, // Alinea botones y número de página.
            children: [
              TextButton(
                onPressed: _page == 0 ? null : () => setState(() => _page--),
                child: const Text('Anterior'),
              ),
              Text(
                'Página ${_page + 1}',
              ), // Presenta una numeración comprensible.
              TextButton(
                onPressed:
                    items.length < SupabaseUserManagementRepository.pageSize
                    ? null
                    : () => setState(() => _page++),
                child: const Text('Siguiente'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
