import 'dart:async'; // Renueva la bandeja para mostrar solicitudes y respuestas nuevas.
import 'package:flutter/material.dart'; // Construye listas de clientes, expedientes y conversaciones.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte los resultados del módulo comercial.
import '../../../auth/presentation/providers/auth_providers.dart'; // Determina las acciones disponibles por rol.
import '../../domain/entities/commerce_models.dart'; // Representa las solicitudes, convenios y chats.
import '../providers/commerce_providers.dart'; // Proporciona consultas y operaciones protegidas.
import '../widgets/commerce_widgets.dart'; // Reutiliza estados y errores.
import 'association_form_page.dart'; // Permite iniciar o corregir la solicitud de un cliente.
import 'association_detail_page.dart'; // Permite revisar datos y tomar una decisión.
import 'support_chat_page.dart'; // Abre el canal de atención correspondiente.

/// Presenta los intentos del cliente o la bandeja de revisión del personal.
class AssociationRequestsPage extends ConsumerWidget {
  const AssociationRequestsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    return CommerceSection(
      title: profile?.canManageOperations == true
          ? 'Solicitudes de convenio'
          : 'Mis solicitudes',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(associationRequestsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
        if (profile?.effectiveRole?.value == 'client')
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AssociationFormPage(customer: profile!),
              ),
            ),
            child: const Text('Nueva solicitud o corregir rechazo'),
          ),
      ],
      children: [
        CommerceAsyncPanel(
          value: ref.watch(associationRequestsProvider),
          onRetry: () => ref.invalidate(associationRequestsProvider),
          builder: (List<AssociationRequest> items) => Column(
            children: [
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hay solicitudes enviadas.'),
                ),
              for (final item in items)
                Card(
                  child: ListTile(
                    title: Text(item.fullName),
                    subtitle: Text(
                      '${item.statusLabel}${item.rejectionReason == null ? '' : '\n${item.rejectionReason}'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AssociationDetailPage(requestId: item.id),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Consulta convenios aceptados conservando acceso a sus documentos originales.
class AgreementsPage extends ConsumerWidget {
  const AgreementsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CommerceSection(
    title: 'Convenios',
    actions: [
      OutlinedButton(
        onPressed: () => ref.invalidate(agreementsProvider),
        child: const Text('Actualizar'),
      ),
      if (ref
              .watch(currentUserProfileProvider)
              .asData
              ?.value
              ?.canManageOperations ==
          true)
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Seleccionar cliente')),
                body: const CustomerAccountsPage(),
              ),
            ),
          ),
          child: const Text('Crear convenio para un cliente'),
        ),
    ],
    children: [
      CommerceAsyncPanel(
        value: ref.watch(agreementsProvider),
        onRetry: () => ref.invalidate(agreementsProvider),
        builder: (List<Agreement> items) => Column(
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Todavía no hay convenios aprobados.'),
              ),
            for (final item in items)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: Text(
                    'Convenio RIT-${item.number.toString().padLeft(6, '0')}',
                  ),
                  subtitle: Text(item.request.fullName),
                  trailing: const Icon(Icons.folder_outlined),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AssociationDetailPage(requestId: item.request.id),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// Permite al personal iniciar la vinculación comercial y atender a cada cliente.
class CustomerAccountsPage extends ConsumerWidget {
  const CustomerAccountsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CommerceSection(
    title: 'Clientes y asociados',
    actions: [
      OutlinedButton(
        onPressed: () => ref.invalidate(customerAccountsProvider),
        child: const Text('Actualizar'),
      ),
    ],
    children: [
      CommerceAsyncPanel(
        value: ref.watch(customerAccountsProvider),
        onRetry: () => ref.invalidate(customerAccountsProvider),
        builder: (items) => Column(
          children: [
            if (items.isEmpty) const Text('No hay clientes registrados.'),
            for (final user in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        user.fullName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${user.email}\n${user.effectiveRole?.label ?? 'Sin rol'}',
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                final id = await ref
                                    .read(commerceRepositoryProvider)
                                    .openConversation(user.id);
                                if (context.mounted) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => SupportChatPage(
                                        conversationId: id,
                                        title: user.fullName,
                                      ),
                                    ),
                                  );
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  showCommerceError(context, error);
                                }
                              }
                            },
                            child: const Text('Atender por chat'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AssociationFormPage(
                                  customer: user,
                                  onBehalf: true,
                                ),
                              ),
                            ),
                            child: const Text('Preparar convenio'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// Muestra notificaciones de solicitudes y respuestas mediante una bandeja de atención.
class SupportInboxPage extends ConsumerStatefulWidget {
  const SupportInboxPage({super.key});
  @override
  ConsumerState<SupportInboxPage> createState() => _SupportInboxPageState();
}

class _SupportInboxPageState extends ConsumerState<SupportInboxPage> {
  Timer?
  _timer; // Renueva el contador de mensajes mientras la bandeja está visible.
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => ref.invalidate(conversationsProvider),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _openOwn() async {
    final profile = ref.read(currentUserProfileProvider).asData?.value;
    if (profile == null) return;
    try {
      final id = await ref
          .read(commerceRepositoryProvider)
          .openConversation(profile.id);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                SupportChatPage(conversationId: id, title: 'Atención Ritech'),
          ),
        );
      }
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff =
        ref
            .watch(currentUserProfileProvider)
            .asData
            ?.value
            ?.canManageOperations ==
        true;
    return CommerceSection(
      title: staff ? 'Atención a clientes' : 'Chat de atención',
      actions: [
        OutlinedButton(
          onPressed: () => ref.invalidate(conversationsProvider),
          child: const Text('Actualizar'),
        ),
        if (!staff)
          FilledButton(
            onPressed: _openOwn,
            child: const Text('Hablar con Ritech'),
          ),
      ],
      children: [
        CommerceAsyncPanel(
          value: ref.watch(conversationsProvider),
          onRetry: () => ref.invalidate(conversationsProvider),
          builder: (List<SupportConversation> items) => Column(
            children: [
              if (items.isEmpty)
                const Text(
                  'Todavía no hay conversaciones. Las solicitudes enviadas aparecerán aquí.',
                ),
              for (final item in items)
                Card(
                  child: ListTile(
                    leading: Badge(
                      isLabelVisible: item.unreadCount > 0,
                      label: Text('${item.unreadCount}'),
                      child: const Icon(Icons.chat_outlined),
                    ),
                    title: Text(staff ? item.clientName : 'Atención Ritech'),
                    subtitle: Text(
                      item.unreadCount > 0
                          ? '${item.unreadCount} mensajes nuevos'
                          : 'Sin mensajes pendientes',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SupportChatPage(
                          conversationId: item.id,
                          title: staff ? item.clientName : 'Atención Ritech',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
