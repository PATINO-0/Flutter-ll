import 'dart:async'; // Actualiza la conversación mientras permanece abierta.
import 'package:flutter/material.dart'; // Construye el historial y el cuadro de respuesta.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Conecta las notificaciones con el dashboard.
import '../../../auth/presentation/providers/auth_providers.dart'; // Identifica al emisor de los mensajes.
import '../../domain/entities/commerce_models.dart'; // Representa los mensajes de texto y del sistema.
import '../providers/commerce_providers.dart'; // Accede al servicio de atención.
import '../widgets/commerce_widgets.dart'; // Presenta errores recuperables.
import 'association_detail_page.dart'; // Permite abrir una solicitud desde su notificación.
import '../../../exports/presentation/export_pages.dart'; // Abre el expediente de una exportación para su titular o revisor.
import '../../../exports/presentation/transport_pages.dart'; // Mantiene el espacio del transportador sin acceso a documentos financieros.

/// Mantiene el historial del cliente y del personal dentro de la misma conversación.
class SupportChatPage extends ConsumerStatefulWidget {
  const SupportChatPage({
    required this.conversationId,
    required this.title,
    super.key,
  });
  final String conversationId; // Identifica el canal autorizado de atención.
  final String
  title; // Presenta el cliente o el equipo de atención según el rol.
  @override
  ConsumerState<SupportChatPage> createState() => _SupportChatPageState();
}

/// Conserva el mensaje escrito, amplía el historial y confirma lecturas sin recrear la página.
class _SupportChatPageState extends ConsumerState<SupportChatPage> {
  final _message = TextEditingController(); // Conserva el mensaje sin enviar.
  late Future<List<SupportMessage>>
  _messages; // Mantiene el historial visible durante las actualizaciones.
  Timer? _timer; // Detiene las consultas periódicas al cerrar el chat.
  bool _sending = false; // Impide enviar el mismo texto dos veces.
  bool _reading = false; // Evita consultas simultáneas del historial.
  int _limit =
      100; // Carga inicialmente el tramo más reciente de la conversación.
  String?
  _lastRead; // Evita registrar varias veces la lectura del mismo mensaje.

  /// Prepara las consultas y recursos locales al abrir la pantalla.
  @override
  void initState() {
    super.initState();
    _messages = _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_reading) _refresh();
    });
  }

  /// Libera los controladores, suscripciones o temporizadores que conserva esta instancia.
  @override
  void dispose() {
    _timer?.cancel();
    _message.dispose();
    super.dispose();
  } // Libera el sondeo y el contenido temporal del chat.

  /// Recupera los datos autorizados y conserva los errores necesarios para reintentar.
  Future<List<SupportMessage>> _load() async {
    _reading = true;
    try {
      final repository = ref.read(commerceRepositoryProvider);
      final messages = await repository.listMessages(
        widget.conversationId,
        limit: _limit,
      );
      if (mounted && messages.isNotEmpty && messages.last.id != _lastRead) {
        await repository.markRead(
          widget.conversationId,
          messages.last.id,
        ); // Solo confirma mensajes efectivamente consultados.
        if (mounted) {
          _lastRead = messages.last.id;
          ref.invalidate(conversationsProvider);
          if (!ref.read(currentUserProfileProvider).isLoading) {
            ref.invalidate(currentUserProfileProvider);
          } // Conserva la comprobación pendiente de roles si ya fue iniciada por el dashboard.
        } // Detecta una promoción o revocación comunicada en el chat.
      }
      return messages;
    } finally {
      _reading = false;
    }
  }

  /// Renueva los datos de esta sección conservando el estado local de su pantalla.
  void _refresh() {
    if (!mounted) return;
    setState(
      () {
        _messages = _load();
      },
    ); // setState requiere una función síncrona que no devuelva el Future de la consulta.
  } // Conserva la pantalla y renueva únicamente su historial.

  /// Conserva el mensaje escrito hasta que el servidor confirme su envío.
  Future<void> _send() async {
    if (_sending || _message.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(commerceRepositoryProvider)
          .sendMessage(widget.conversationId, _message.text);
      if (mounted) {
        _message.clear();
        _refresh();
      }
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) {
    final userId = ref
        .watch(authRepositoryProvider)
        .currentUserId; // Distingue mensajes propios sin confiar en el texto del remitente.
    final transporter =
        ref
            .watch(currentUserProfileProvider)
            .asData
            ?.value
            ?.effectiveRole
            ?.value ==
        'transporter'; // Limita el enlace de una notificación al espacio autorizado del transportador.
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Actualizar conversación',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<List<SupportMessage>>(
                future: _messages,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    if (snapshot.hasError) {
                      return Center(
                        child: TextButton(
                          onPressed: _refresh,
                          child: const Text(
                            'No fue posible cargar el chat. Reintentar',
                          ),
                        ),
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data!;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (items.length >= _limit)
                        TextButton(
                          onPressed: () {
                            _limit += 100;
                            _refresh();
                          },
                          child: const Text('Cargar mensajes anteriores'),
                        ),
                      if (items.isEmpty)
                        const Text(
                          'Escribe tu consulta. El equipo de Ritech te responderá por este medio.',
                        ),
                      for (final item in items)
                        Align(
                          alignment: item.kind == 'system'
                              ? Alignment.center
                              : item.senderId == userId
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 650),
                            child: Card(
                              color: item.kind == 'system'
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.kind == 'system'
                                          ? 'Notificación de la solicitud'
                                          : item.senderId == userId
                                          ? 'Tú'
                                          : 'Atención',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelMedium,
                                    ),
                                    SelectableText(item.body),
                                    Text(
                                      '${item.createdAt.toLocal().day}/${item.createdAt.toLocal().month}/${item.createdAt.toLocal().year} ${item.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${item.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                    if (item.requestId != null)
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    AssociationDetailPage(
                                                      requestId:
                                                          item.requestId!,
                                                    ),
                                              ),
                                            ),
                                        child: const Text(
                                          'Ver solicitud y documentos',
                                        ),
                                      ),
                                    if (item.exportRequestId != null)
                                      TextButton(
                                        onPressed: () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => transporter
                                                ? Scaffold(
                                                    appBar: AppBar(
                                                      title: const Text(
                                                        'Envíos de café',
                                                      ),
                                                    ),
                                                    body:
                                                        const TransportJobsPage(),
                                                  )
                                                : CoffeeExportDetailPage(
                                                    requestId:
                                                        item.exportRequestId!,
                                                  ),
                                          ),
                                        ),
                                        child: Text(
                                          transporter
                                              ? 'Ver envíos para tomar o actualizar'
                                              : 'Ver exportación y documentos',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (snapshot.hasError)
                        const Text(
                          'No se pudo actualizar la conversación. Se muestra el último historial disponible.',
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _message,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 4000,
                      decoration: const InputDecoration(
                        labelText: 'Escribe tu mensaje',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Enviar mensaje',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
