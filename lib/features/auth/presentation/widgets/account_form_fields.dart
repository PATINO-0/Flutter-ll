import 'package:flutter/material.dart'; // Construye los campos del formulario.

import '../../../../core/utils/validators.dart'; // Comparte las validaciones de las cuentas.

/// Reutiliza los datos de registro público y de creación administrativa.
class AccountFormFields extends StatefulWidget {
  const AccountFormFields({
    required this.nameController, // Recibe el nombre del formulario propietario.
    required this.emailController, // Recibe el correo del formulario propietario.
    required this.passwordController, // Recibe la contraseña sin almacenarla en el perfil.
    required this.confirmController, // Recibe la confirmación de la contraseña.
    required this.enabled, // Bloquea los campos mientras se envía la solicitud.
    super.key,
  });

  final TextEditingController nameController; // Controla el nombre completo.
  final TextEditingController
  emailController; // Controla el correo electrónico.
  final TextEditingController
  passwordController; // Controla la contraseña nueva.
  final TextEditingController
  confirmController; // Controla la segunda entrada de contraseña.
  final bool enabled; // Indica si se permite editar el formulario.

  @override
  State<AccountFormFields> createState() => _AccountFormFieldsState();
}

/// Mantiene únicamente el estado visual de la contraseña.
class _AccountFormFieldsState extends State<AccountFormFields> {
  bool _obscurePassword = true; // Oculta las contraseñas inicialmente.

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller:
              widget.nameController, // Vincula el nombre con su controlador.
          enabled: widget.enabled, // Evita cambios durante el envío.
          validator: Validators.fullName, // Verifica los límites del nombre.
          maxLength: 100, // Refleja el límite del servidor.
          textCapitalization:
              TextCapitalization.words, // Facilita escribir nombres propios.
          textInputAction:
              TextInputAction.next, // Continúa al correo electrónico.
          autofillHints: const [
            AutofillHints.name,
          ], // Permite completar el nombre guardado.
          decoration: const InputDecoration(labelText: 'Nombre completo'),
        ),
        const SizedBox(height: 16), // Separa visualmente los campos.
        TextFormField(
          controller:
              widget.emailController, // Vincula el correo con su controlador.
          enabled: widget.enabled, // Bloquea cambios durante el envío.
          validator: Validators.email, // Comprueba el formato del correo.
          keyboardType:
              TextInputType.emailAddress, // Muestra el teclado de correo.
          textInputAction: TextInputAction.next, // Continúa a la contraseña.
          autofillHints: const [
            AutofillHints.email,
          ], // Facilita completar el correo.
          decoration: const InputDecoration(labelText: 'Correo electrónico'),
        ),
        const SizedBox(height: 16), // Separa la contraseña del correo.
        TextFormField(
          controller: widget.passwordController, // Vincula la nueva contraseña.
          enabled: widget.enabled, // Impide modificar una solicitud en curso.
          validator: Validators
              .newPassword, // Exige la longitud admitida por el servidor.
          obscureText: _obscurePassword, // Aplica la visibilidad seleccionada.
          enableSuggestions: false, // Evita sugerencias sobre datos sensibles.
          autocorrect: false, // Conserva exactamente los caracteres ingresados.
          textInputAction: TextInputAction.next, // Continúa a la confirmación.
          autofillHints: const [
            AutofillHints.newPassword,
          ], // Permite generar una contraseña.
          decoration: InputDecoration(
            labelText: 'Contraseña', // Identifica el campo de contraseña.
            helperText:
                'Entre 8 y 72 caracteres.', // Explica el requisito antes de enviar.
            suffixIcon: IconButton(
              tooltip: _obscurePassword
                  ? 'Mostrar contraseña'
                  : 'Ocultar contraseña',
              onPressed: widget.enabled
                  ? () => setState(() => _obscurePassword = !_obscurePassword)
                  : null, // Desactiva el cambio de visibilidad durante el envío.
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16), // Separa la confirmación de la contraseña.
        TextFormField(
          controller: widget.confirmController, // Vincula la segunda entrada.
          enabled:
              widget.enabled, // Mantiene consistente la solicitud en curso.
          validator: (value) =>
              Validators.confirmPassword(value, widget.passwordController.text),
          obscureText:
              _obscurePassword, // Comparte la visibilidad de la contraseña.
          enableSuggestions: false, // Evita sugerencias sobre la confirmación.
          autocorrect: false, // No modifica los caracteres ingresados.
          autofillHints: const [
            AutofillHints.newPassword,
          ], // Permite completar la misma contraseña.
          decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
        ),
      ],
    );
  }
}
