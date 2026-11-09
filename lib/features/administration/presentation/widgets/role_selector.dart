import 'package:flutter/material.dart'; // Construye los controles de selección.

import '../../../auth/domain/entities/user_role.dart'; // Define los roles y sus explicaciones.

/// Permite seleccionar varios roles de forma explícita.
class RoleSelector extends StatelessWidget {
  const RoleSelector({
    required this.selected,
    required this.onChanged,
    required this.enabled,
    super.key,
  });

  final Set<UserRole>
  selected; // Contiene los roles seleccionados en el formulario.
  final ValueChanged<Set<UserRole>>
  onChanged; // Notifica una nueva selección sin modificar el perfil original.
  final bool enabled; // Evita modificaciones durante el guardado.

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final role
            in UserRole
                .values) // Presenta todos los roles admitidos por el servidor.
          CheckboxListTile(
            contentPadding:
                EdgeInsets.zero, // Alinea las opciones con el formulario.
            title: Text(role.label), // Muestra el nombre del rol en español.
            subtitle: Text(
              role.description,
            ), // Explica las funciones asociadas.
            value: selected.contains(role), // Refleja la selección actual.
            onChanged: enabled
                ? (checked) {
                    final roles = Set<UserRole>.from(
                      selected,
                    ); // Copia la selección antes de modificarla.
                    if (checked == true) {
                      roles.add(role); // Añade el permiso seleccionado.
                    } else {
                      roles.remove(role); // Retira el permiso desmarcado.
                    }
                    onChanged(
                      roles,
                    ); // Entrega la selección actualizada al formulario.
                  }
                : null,
          ),
      ],
    );
  }
}
