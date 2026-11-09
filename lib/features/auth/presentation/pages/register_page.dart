import 'package:flutter/material.dart'; // Construye la pantalla de registro.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Accede al controlador de autenticación.
import 'package:go_router/go_router.dart'; // Permite volver al inicio de sesión.

import '../../../../core/constants/app_routes.dart'; // Comparte las rutas de la aplicación.
import '../../../../shared/widgets/app_brand.dart'; // Muestra la identidad de Ritech.
import '../providers/auth_providers.dart'; // Proporciona el registro y su estado de carga.
import '../widgets/account_form_fields.dart'; // Reutiliza los campos y sus validaciones.

/// Permite que cualquier persona cree su cuenta de cliente.
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

/// Conserva los datos del formulario hasta completar el registro.
class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey =
      GlobalKey<FormState>(); // Agrupa las validaciones del registro.
  final _nameController =
      TextEditingController(); // Conserva el nombre ingresado.
  final _emailController =
      TextEditingController(); // Conserva el correo ingresado.
  final _passwordController =
      TextEditingController(); // Conserva temporalmente la contraseña.
  final _confirmController =
      TextEditingController(); // Conserva temporalmente su confirmación.
  bool _registered = false; // Indica que falta confirmar el correo.

  @override
  void dispose() {
    _nameController.dispose(); // Libera el controlador del nombre.
    _emailController.dispose(); // Libera el controlador del correo.
    _passwordController.dispose(); // Libera la contraseña de la pantalla.
    _confirmController.dispose(); // Libera la confirmación de la pantalla.
    super.dispose(); // Completa la liberación del estado visual.
  }

  /// Valida el formulario y solicita una cuenta sin roles privilegiados.
  Future<void> _submit() async {
    if (ref.read(authControllerProvider).isLoading) {
      return; // Evita registros duplicados.
    }
    if (!_formKey.currentState!.validate()) {
      return; // Presenta los errores antes de enviar.
    }
    FocusScope.of(context).unfocus(); // Cierra el teclado durante la solicitud.
    final message = await ref
        .read(authControllerProvider.notifier)
        .signUp(
          fullName:
              _nameController.text, // Entrega el nombre para crear el perfil.
          email: _emailController.text, // Entrega el correo de acceso.
          password: _passwordController
              .text, // Entrega la contraseña solamente a autenticación.
        );
    if (!mounted) {
      return; // Evita acceder a una pantalla cerrada por la navegación.
    }
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return; // Mantiene el formulario disponible para corregir el error.
    }
    _passwordController
        .clear(); // Retira la contraseña después de completar el registro.
    _confirmController.clear(); // Retira también su confirmación.
    if (!ref.read(authRepositoryProvider).hasSession) {
      setState(
        () => _registered = true,
      ); // Explica la confirmación cuando no hay sesión automática.
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref
        .watch(authControllerProvider)
        .isLoading; // Observa el envío del registro.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta'),
      ), // Identifica el registro público.
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(
              24,
            ), // Deja espacio para pantallas pequeñas.
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 460,
              ), // Limita el ancho de lectura.
              child: Form(
                key: _formKey, // Conecta la validación con el envío.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment
                      .stretch, // Alinea los campos y botones.
                  children: [
                    const Center(
                      child: AppBrand(),
                    ), // Presenta la marca de la aplicación.
                    const SizedBox(
                      height: 24,
                    ), // Separa la marca del contenido.
                    if (_registered) ...[
                      const Icon(Icons.mark_email_read_outlined, size: 56),
                      const SizedBox(
                        height: 16,
                      ), // Separa el aviso de su icono.
                      const Text(
                        'Revisa tu correo',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(
                        height: 12,
                      ), // Facilita la lectura de las instrucciones.
                      const Text(
                        'Si el correo puede registrarse, recibirás un enlace de confirmación. '
                        'Confírmalo y regresa para iniciar sesión. Si ya tienes una cuenta, inicia sesión con ella.',
                        textAlign: TextAlign
                            .center, // Mantiene claro el siguiente paso sin revelar cuentas existentes.
                      ),
                    ] else ...[
                      const Text(
                        'Regístrate para acceder a Ritech como cliente.',
                      ),
                      const SizedBox(
                        height: 24,
                      ), // Separa la explicación de los campos.
                      AccountFormFields(
                        nameController:
                            _nameController, // Comparte el nombre con el formulario.
                        emailController:
                            _emailController, // Comparte el correo con el formulario.
                        passwordController:
                            _passwordController, // Comparte la contraseña temporal.
                        confirmController:
                            _confirmController, // Comparte la confirmación temporal.
                        enabled:
                            !loading, // Bloquea los campos durante el registro.
                      ),
                      const SizedBox(
                        height: 24,
                      ), // Separa los campos del botón principal.
                      FilledButton(
                        onPressed: loading
                            ? null
                            : _submit, // Ejecuta una única solicitud a la vez.
                        child: Text(
                          loading ? 'Creando cuenta…' : 'Crear cuenta',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16), // Separa la acción de regreso.
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => context.go(AppRoutes.login),
                      child: const Text('Volver a iniciar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
