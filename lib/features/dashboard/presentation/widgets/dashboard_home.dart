import 'package:flutter/material.dart'; // Construye la bienvenida personalizada.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../commerce/presentation/providers/commerce_providers.dart';
import '../../../exports/presentation/export_providers.dart';
import '../../../exports/domain/export_models.dart';

import '../../../auth/domain/entities/user_profile.dart'; // Proporciona el nombre y los roles asignados.

/// Explica las funciones disponibles de acuerdo con los roles actuales del usuario.
class DashboardHome extends ConsumerWidget {
  const DashboardHome({required this.profile, super.key});

  final UserProfile profile; // Recibe el perfil cargado desde el servidor.

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!profile.canAccessCoffee) {
      return const Center(
        child: Text('No tienes acceso al dashboard de café.'),
      );
    }
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panel principal',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bienvenido, ${profile.fullName}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Acceso actual: ${profile.effectiveRole?.label ?? 'Sin rol asignado'}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (profile.canAccessCoffee) ...[
                const SizedBox(height: 24),
                Text(
                  profile.canManageOperations
                      ? 'Resumen general de café'
                      : 'Mis operaciones de café',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Los indicadores incluyen únicamente los datos que puedes consultar.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.invalidate(coffeeExportLotsProvider);
                      ref.invalidate(coffeeExportRequestsProvider);
                      ref.invalidate(coffeeShipmentsProvider);
                      if (profile.canManageOperations) {
                        ref.invalidate(customerAccountsProvider);
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar indicadores'),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final count = profile.canManageOperations ? 4 : 3;
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(14) > 20;
                    final columns = largeText || constraints.maxWidth < 460
                        ? 1
                        : constraints.maxWidth >= 900
                        ? count
                        : 2;
                    final width =
                        (constraints.maxWidth - 12 * (columns - 1)) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _DashboardMetric(
                          width: width,
                          icon: Icons.coffee_outlined,
                          title: 'Lotes de café',
                          value: ref
                              .watch(coffeeExportLotsProvider)
                              .whenData((rows) => '${rows.length}'),
                        ),
                        if (profile.canManageOperations)
                          _DashboardMetric(
                            width: width,
                            icon: Icons.people_outline,
                            title: 'Clientes y asociados',
                            value: ref
                                .watch(customerAccountsProvider)
                                .whenData((rows) => '${rows.length}'),
                          ),
                        _DashboardMetric(
                          width: width,
                          icon: Icons.description_outlined,
                          title: 'Solicitudes de exportación',
                          value: ref
                              .watch(coffeeExportRequestsProvider)
                              .whenData((rows) => '${rows.length}'),
                        ),
                        _DashboardMetric(
                          width: width,
                          icon: Icons.task_alt,
                          title: 'Exportaciones aceptadas',
                          value: ref
                              .watch(coffeeExportRequestsProvider)
                              .whenData(
                                (rows) =>
                                    '${rows.where((row) => row.status == 'approved').length}',
                              ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                _statusPanel(
                  context,
                  title: 'Solicitudes por estado',
                  icon: Icons.assignment_outlined,
                  child: _DashboardStates<CoffeeExportRequest>(
                    value: ref.watch(coffeeExportRequestsProvider),
                    states: const {
                      'draft': 'Borrador',
                      'pending': 'En revisión',
                      'approved': 'Aceptada',
                      'rejected': 'Devuelta',
                    },
                    statusOf: (row) => row.status,
                  ),
                ),
                const SizedBox(height: 16),
                _statusPanel(
                  context,
                  title: 'Transporte por estado',
                  icon: Icons.local_shipping_outlined,
                  child: _DashboardStates<CoffeeShipment>(
                    value: ref.watch(coffeeShipmentsProvider),
                    states: coffeeDeliveryStatuses,
                    statusOf: (row) => row.status,
                  ),
                ),
              ],
              const SizedBox(
                height: 24,
              ), // Separa el saludo de la información de acceso.
              Text('Tus roles en Ritech', style: theme.textTheme.titleLarge),
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

  /// Agrupa cada etapa sin mezclar solicitudes con estados de transporte.
  Widget _statusPanel(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

/// Presenta un indicador sin convertir errores de consulta en un cero engañoso.
class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
    required this.title,
    required this.value,
    required this.icon,
    required this.width,
  });
  final String title;
  final AsyncValue<String> value;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(height: 16),
            value.when(
              data: (count) => Text(
                count,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) =>
                  const Text('No disponible. Actualiza para reintentar.'),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Agrupa estados autorizados y conserva los estados nuevos sin omitir registros.
class _DashboardStates<T> extends StatelessWidget {
  const _DashboardStates({
    required this.value,
    required this.states,
    required this.statusOf,
  });
  final AsyncValue<List<T>> value;
  final Map<String, String> states;
  final String Function(T) statusOf;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const LinearProgressIndicator(),
    error: (_, _) => const Text(
      'No fue posible consultar los estados. Actualiza para reintentar.',
    ),
    data: (rows) {
      final counts = {for (final state in states.keys) state: 0};
      for (final row in rows) {
        final state = statusOf(row);
        counts[state] = (counts[state] ?? 0) + 1;
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in counts.entries)
            Chip(
              label: Text('${states[entry.key] ?? entry.key}: ${entry.value}'),
            ),
        ],
      );
    },
  );
}
