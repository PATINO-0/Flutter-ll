import 'customer_accounts_page.dart'; // Comparte la consulta y el cierre de convenios del cliente.
export 'customer_accounts_page.dart'; // Conserva los accesos existentes al listado comercial.
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
import '../../../exports/presentation/export_providers.dart'; // Abre la coordinación restringida con el transportador.
import '../widgets/agreement_actions.dart'; // Presenta vigencia y estado sin confundir revisión con aceptación.

/// Presenta los intentos del cliente o la bandeja de revisión del personal.
class AssociationRequestsPage extends ConsumerWidget {
  const AssociationRequestsPage({super.key});

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
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

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
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
                child: Text(
                  'Todavía no hay convenios ni propuestas registrados.',
                ),
              ),
            for (final item in items)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: Text(
                    'Convenio RIT-${item.number.toString().padLeft(6, '0')}',
                  ),
                  subtitle: Text(
                    '${item.request.fullName}\n${item.statusLabel}\nVigencia: ${agreementDate(item.expiresAt)}${item.closureReason == null ? '' : '\nMotivo de cierre: ${item.closureReason}'}',
                  ),
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

/// Muestra notificaciones de solicitudes y respuestas mediante una bandeja de atención.
class SupportInboxPage extends ConsumerStatefulWidget {
  const SupportInboxPage({this.channel = 'support', super.key});
  final String
  channel; // Mantiene las solicitudes de envío fuera de la atención general.
  @override
  ConsumerState<SupportInboxPage> createState() => _SupportInboxPageState();
}

/// Sondea conversaciones sin duplicar consultas y abre exclusivamente los chats permitidos.
class _SupportInboxPageState extends ConsumerState<SupportInboxPage> {
  /// Filtra conversaciones por canal sin ampliar los permisos que aplica el servidor.
  bool _matches(SupportConversation item, bool staff) =>
      widget.channel == 'exports'
      ? (item.channel == 'exports' || staff && item.channel == 'transport')
      : item.channel ==
            widget
                .channel; // La base de datos mantiene además el aislamiento por participante.
  Timer?
  _timer; // Renueva el contador de mensajes mientras la bandeja está visible.
  /// Prepara las consultas y recursos locales al abrir la pantalla.
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!ref.read(conversationsProvider).isLoading) {
        ref.invalidate(conversationsProvider);
      } // Una conexión lenta no inicia consultas simultáneas de la misma bandeja.
    });
  }

  /// Libera los controladores, suscripciones o temporizadores que conserva esta instancia.
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Abre exclusivamente la conversación propia que corresponde al canal y rol actuales.
  Future<void> _openOwn() async {
    final profile = ref.read(currentUserProfileProvider).asData?.value;
    if (profile == null) return;
    try {
      final id = widget.channel == 'transport'
          ? await ref
                .read(coffeeExportsRepositoryProvider)
                .transportConversation(profile.id)
          : await ref
                .read(commerceRepositoryProvider)
                .openConversation(profile.id);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SupportChatPage(
              conversationId: id,
              title: widget.channel == 'transport'
                  ? 'Chat con el empleado'
                  : 'Atención Ritech',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    }
  }

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
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
      title: widget.channel == 'exports'
          ? 'Envíos y coordinación'
          : widget.channel == 'transport'
          ? 'Chat con el empleado'
          : staff
          ? 'Atención a clientes'
          : 'Chat de atención',
      actions: [
        OutlinedButton(
          onPressed: () => ref.invalidate(conversationsProvider),
          child: const Text('Actualizar'),
        ),
        if (!staff && widget.channel != 'exports')
          FilledButton(
            onPressed: _openOwn,
            child: Text(
              widget.channel == 'transport'
                  ? 'Contactar al empleado'
                  : 'Hablar con Ritech',
            ),
          ),
      ],
      children: [
        CommerceAsyncPanel(
          value: ref.watch(conversationsProvider),
          onRetry: () => ref.invalidate(conversationsProvider),
          builder: (List<SupportConversation> items) => Column(
            children: [
              if (items.where((item) => _matches(item, staff)).isEmpty)
                const Text(
                  'Todavía no hay conversaciones. Las solicitudes enviadas aparecerán aquí.',
                ),
              for (final item in items.where((item) => _matches(item, staff)))
                Card(
                  child: ListTile(
                    leading: Badge(
                      isLabelVisible: item.unreadCount > 0,
                      label: Text('${item.unreadCount}'),
                      child: const Icon(Icons.chat_outlined),
                    ),
                    title: Text(
                      widget.channel != 'support' || staff
                          ? item.clientName
                          : 'Atención Ritech',
                    ),
                    subtitle: Text(
                      item.unreadCount > 0
                          ? '${item.unreadCount} mensajes nuevos'
                          : 'Sin mensajes pendientes',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SupportChatPage(
                          conversationId: item.id,
                          title: widget.channel != 'support' || staff
                              ? item.clientName
                              : 'Atención Ritech',
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
