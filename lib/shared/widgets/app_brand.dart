import 'package:flutter/material.dart'; // Construye los controles y estilos Material de la interfaz.

/// Presenta la identidad visual de Ritech en sus variantes completa y compacta.
class AppBrand extends StatelessWidget {
  const AppBrand({super.key, this.compact = false});

  final bool compact;

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 42 : 50,
          height: compact ? 42 : 50,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons
                .local_shipping_rounded, // Representa los servicios logísticos de Ritech.
            color: theme.colorScheme.onPrimary,
            size: compact ? 24 : 28,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ritech', // Presenta el nombre de la aplicación.
                style: compact
                    ? theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )
                    : theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
              ),
              if (!compact)
                Text(
                  'Envíos, seguimiento y convenios', // Resume los servicios de la aplicación.
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
