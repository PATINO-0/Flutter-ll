import 'package:flutter/material.dart'; // Construye el formulario de administración.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Accede al repositorio del módulo.

import '../../../../core/errors/app_exception.dart'; // Muestra los errores controlados del servidor.
import '../../../../core/utils/validators.dart'; // Comparte las reglas del nombre y el correo de acceso.
import '../../../auth/domain/entities/user_profile.dart'; // Recibe el perfil cuando se editan roles.
import '../../../auth/domain/entities/user_role.dart'; // Mantiene la selección de permisos.
import '../../../auth/presentation/widgets/account_form_fields.dart'; // Reutiliza los campos de la cuenta.
import '../providers/administration_providers.dart'; // Proporciona las operaciones protegidas.
import 'role_selector.dart'; // Presenta la selección múltiple de roles.

/// Crea una cuenta o modifica solamente los roles de una cuenta existente.
class UserEditorDialog extends ConsumerStatefulWidget {
  const UserEditorDialog({this.profile, super.key});

  final UserProfile? profile; // Un valor nulo activa la creación de una cuenta.

  @override
  ConsumerState<UserEditorDialog> createState() => _UserEditorDialogState();
}

/// Mantiene los cambios locales hasta que el servidor confirma el guardado.
class _UserEditorDialogState extends ConsumerState<UserEditorDialog> {
  final _formKey =
      GlobalKey<FormState>(); // Agrupa la validación de los datos nuevos.
  final _nameController =
      TextEditingController(); // Conserva el nombre de la cuenta nueva.
  final _emailController =
      TextEditingController(); // Conserva el correo de la cuenta nueva.
  final _passwordController =
      TextEditingController(); // Conserva temporalmente la contraseña inicial.
  final _confirmController =
      TextEditingController(); // Verifica la contraseña inicial.
  late Set<UserRole> _roles; // Mantiene una copia editable de los roles.
  bool _saving =
      false; // Impide guardar dos veces o cerrar durante una operación.
  String? _error; // Presenta el error junto al formulario sin perder sus datos.

  @override
  void initState() {
    super.initState(); // Inicializa el estado del diálogo.
    _roles = (widget.profile?.roles ?? [UserRole.client])
        .toSet(); // Conserva roles existentes o propone cliente.
    _nameController.text =
        widget.profile?.fullName ??
        ''; // Permite corregir los datos del usuario seleccionado.
    _emailController.text =
        widget.profile?.email ??
        ''; // Presenta el correo de acceso que también se actualizará en Auth.
  }

  @override
  void dispose() {
    _nameController.dispose(); // Libera el controlador del nombre.
    _emailController.dispose(); // Libera el controlador del correo.
    _passwordController.dispose(); // Libera la contraseña temporal.
    _confirmController.dispose(); // Libera la confirmación temporal.
    super.dispose(); // Completa la liberación del diálogo.
  }

  /// Envía la operación apropiada sin alterar la sesión administrativa.
  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return; // Rechaza envíos duplicados o inválidos.
    }
    if (widget.profile == null && _roles.isEmpty) {
      setState(
        () => _error = 'Selecciona al menos un rol para la cuenta nueva.',
      );
      return; // Requiere una responsabilidad inicial para la cuenta creada.
    }
    setState(() {
      _saving = true;
      _error = null;
    }); // Bloquea el formulario y limpia el aviso anterior.
    try {
      final repository = ref.read(
        userManagementRepositoryProvider,
      ); // Obtiene la operación autenticada.
      final profile = widget
          .profile; // Comprueba explícitamente si se edita una cuenta existente.
      if (profile != null) {
        await repository.updateUser(
          userId: profile.id,
          fullName: _nameController
              .text, // Guarda el nombre corregido junto con los roles.
          email: _emailController
              .text, // Sincroniza el correo de la cuenta de acceso.
          roles: _roles.toList(),
        ); // Reemplaza los roles en una transacción.
      } else {
        await repository.createUser(
          fullName: _nameController.text, // Envía el nombre del nuevo usuario.
          email: _emailController.text, // Envía su correo de acceso.
          password: _passwordController
              .text, // Entrega la contraseña inicial al servidor.
          roles: _roles
              .toList(), // Solicita los roles elegidos por el administrador.
        );
      }
      if (mounted) {
        Navigator.of(
          context,
        ).pop(true); // Informa que la lista debe actualizarse.
      }
    } on AppException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.userMessage,
        ); // Conserva el formulario para corregir el problema.
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No fue posible guardar los cambios.');
      }
    } finally {
      if (mounted) {
        setState(
          () => _saving = false,
        ); // Restablece los controles tras completar la solicitud.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating =
        widget.profile == null; // Decide qué campos necesita el formulario.
    return PopScope(
      canPop: !_saving, // Evita abandonar una creación o asignación en curso.
      child: AlertDialog(
        title: Text(creating ? 'Crear usuario' : 'Actualizar usuario'),
        content: SizedBox(
          width: 460, // Mantiene legibles los campos en escritorio y móvil.
          child: SingleChildScrollView(
            child: Form(
              key:
                  _formKey, // Conecta las validaciones con el botón de guardar.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment
                    .stretch, // Alinea los datos y las opciones.
                children: [
                  if (creating)
                    AccountFormFields(
                      nameController:
                          _nameController, // Recibe el nombre de la cuenta nueva.
                      emailController:
                          _emailController, // Recibe su correo electrónico.
                      passwordController:
                          _passwordController, // Recibe su contraseña inicial.
                      confirmController:
                          _confirmController, // Comprueba la contraseña inicial.
                      enabled:
                          !_saving, // Desactiva cambios durante la solicitud.
                    )
                  else
                    Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          enabled: !_saving,
                          validator: Validators.fullName,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          enabled: !_saving,
                          validator: Validators.email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(
                    height: 20,
                  ), // Separa los datos personales de los permisos.
                  const Text(
                    'Roles del usuario',
                  ), // Identifica la selección de funciones.
                  RoleSelector(
                    selected: _roles, // Presenta los permisos seleccionados.
                    enabled: !_saving, // Impide cambios durante el guardado.
                    onChanged: (roles) => setState(
                      () => _roles = roles,
                    ), // Actualiza solamente la selección local.
                  ),
                  Text(
                    creating
                        ? 'La cuenta quedará habilitada con esta contraseña inicial. Comunícala al usuario por un canal privado.'
                        : 'Sin roles, el usuario conservará únicamente el acceso a su panel principal.',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 16,
                      ), // Separa el error de las opciones.
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
    );
  }
}
