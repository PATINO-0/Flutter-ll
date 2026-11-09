import 'package:flutter/material.dart'; // Presenta clientes, vigencia y acciones de vinculación.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte clientes y convenios protegidos.
import '../providers/commerce_providers.dart'; // Ejecuta consultas y notificaciones del flujo comercial.
import '../widgets/commerce_widgets.dart'; // Conserva estados de consulta y errores comprensibles.
import '../widgets/agreement_actions.dart'; // Recoge el motivo de revocación y presenta fechas.
import 'association_form_page.dart'; // Prepara una propuesta que deberá aceptar el titular.
import 'association_detail_page.dart'; // Abre el expediente, sus documentos y su aceptación.
import 'support_chat_page.dart'; // Contacta al cliente desde su canal de atención.

/// Permite al empleado y administrador gestionar una vinculación vigente por cliente.
class CustomerAccountsPage extends ConsumerWidget {
  const CustomerAccountsPage({super.key});

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agreements = ref.watch(
      agreementsProvider,
    ); // Una consulta pendiente no habilita propuestas duplicadas por suposición.
    return CommerceSection(
      title: 'Clientes y asociados',
      actions: [
        OutlinedButton(
          onPressed: () {
            ref.invalidate(customerAccountsProvider);
            ref.invalidate(agreementsProvider);
          },
          child: const Text('Actualizar'),
        ),
      ],
      children: [
        if (agreements.hasError)
          const Text(
            'No fue posible verificar los convenios. Actualiza la información antes de preparar otro.',
          ),
        CommerceAsyncPanel(
          value: ref.watch(customerAccountsProvider),
          onRetry: () => ref.invalidate(customerAccountsProvider),
          builder: (users) => Column(
            children: [
              if (users.isEmpty) const Text('No hay clientes registrados.'),
              for (final user in users)
                Builder(
                  builder: (context) {
                    final open = agreements.asData?.value
                        .where(
                          (agreement) =>
                              agreement.request.ownerId == user.id &&
                              agreement.isOpen,
                        )
                        .firstOrNull;
                    return Card(
                      key: ValueKey(user.id),
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
                            Text(
                              open == null
                                  ? agreements.hasValue
                                        ? 'Sin convenio vigente.'
                                        : 'Verificando convenio…'
                                  : '${open.statusLabel}\nVigencia: ${agreementDate(open.expiresAt)}',
                            ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () async {
                                    try {
                                      final chat = await ref
                                          .read(commerceRepositoryProvider)
                                          .openConversation(user.id);
                                      if (context.mounted) {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => SupportChatPage(
                                              conversationId: chat,
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
                                if (open == null &&
                                    agreements.hasValue &&
                                    !agreements.hasError)
                                  FilledButton(
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => AssociationFormPage(
                                            customer: user,
                                            onBehalf: true,
                                          ),
                                        ),
                                      );
                                      if (context.mounted) {
                                        ref.invalidate(agreementsProvider);
                                      }
                                    },
                                    child: const Text('Preparar convenio'),
                                  ),
                                if (open != null) ...[
                                  OutlinedButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => AssociationDetailPage(
                                          requestId: open.request.id,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'Ver convenio y documentos',
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => showAgreementAction(
                                      context,
                                      ref,
                                      agreementId: open.id,
                                      requestId: open.request.id,
                                      action: 'revoke',
                                    ),
                                    child: const Text(
                                      'Revocar convenio con motivo',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
