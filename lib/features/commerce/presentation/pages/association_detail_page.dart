import 'package:flutter/material.dart'; // Presenta el expediente y la decisión del trabajador.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Actualiza el convenio y los roles después de resolverlo.
import '../../../auth/presentation/providers/auth_providers.dart'; // Comprueba si la sesión puede revisar solicitudes.
import '../../domain/entities/commerce_models.dart'; // Describe el expediente y sus documentos privados.
import '../providers/commerce_providers.dart'; // Consulta y modifica el flujo mediante el repositorio.
import '../widgets/commerce_widgets.dart'; // Comparte estados y errores del módulo.

class AssociationDetailPage extends ConsumerStatefulWidget {
  const AssociationDetailPage({required this.requestId, super.key});
  final String
  requestId; // Identifica el expediente abierto desde un chat o convenio.
  @override
  ConsumerState<AssociationDetailPage> createState() =>
      _AssociationDetailPageState();
}

class _AssociationDetailPageState extends ConsumerState<AssociationDetailPage> {
  bool _busy = false; // Impide decisiones simultáneas desde la misma pantalla.

  Future<void> _review(bool approve) async {
    final reason =
        TextEditingController(); // Conserva el motivo del rechazo únicamente durante la confirmación.
    final form =
        GlobalKey<
          FormState
        >(); // Verifica que el rechazo explique las correcciones necesarias.
    final confirmed = await showCommerceDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Aprobar convenio' : 'Rechazar solicitud'),
        content: approve
            ? const Text(
                'Se creará el convenio con los documentos enviados y el cliente pasará a ser asociado.',
              )
            : Form(
                key: form,
                child: TextFormField(
                  controller: reason,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Motivo y correcciones requeridas',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 5
                      ? 'Explica el motivo con al menos 5 caracteres.'
                      : null,
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (approve || form.currentState!.validate()) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    final explanation = reason.text;
    reason.dispose(); // Retira el controlador sin perder el texto confirmado.
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(commerceRepositoryProvider)
          .reviewRequest(
            widget.requestId,
            approve: approve,
            reason: explanation,
          );
      if (!mounted) return;
      ref.invalidate(associationRequestProvider(widget.requestId));
      ref.invalidate(associationRequestsProvider);
      ref.invalidate(agreementsProvider);
      ref.invalidate(customerAccountsProvider);
      ref.invalidate(conversationsProvider);
      ref.invalidate(
        currentUserProfileProvider,
      ); // Actualiza todos los módulos afectados por la decisión.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Convenio aprobado y asociado habilitado.'
                : 'Rechazo enviado al cliente por el chat.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(associationRequestProvider(widget.requestId));
    final staff =
        ref
            .watch(currentUserProfileProvider)
            .asData
            ?.value
            ?.canManageOperations ==
        true; // Oculta las decisiones a clientes y asociados.
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitud de convenio')),
      body: CommerceAsyncPanel(
        value: request,
        onRetry: () =>
            ref.invalidate(associationRequestProvider(widget.requestId)),
        builder: (AssociationRequest item) => CommerceSection(
          title: item.fullName,
          children: [
            Chip(label: Text(item.statusLabel)),
            Text(
              'Identificación: ${item.identityNumber}\nContacto: ${item.phone}\nDirección: ${item.address}\nActividad: ${item.businessDescription}',
            ),
            if (item.rejectionReason != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Correcciones solicitadas: ${item.rejectionReason}',
                ),
              ),
            const SizedBox(height: 16),
            const Text('Documentos del expediente'),
            for (final document in item.documents)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(document.name),
                trailing: IconButton(
                  tooltip: 'Abrir documento privado',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () async {
                    try {
                      await ref
                          .read(commerceRepositoryProvider)
                          .openDocument(document.path);
                    } catch (error) {
                      if (context.mounted) showCommerceError(context, error);
                    }
                  },
                ),
              ),
            if (staff && item.status == 'pending')
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => _review(true),
                    child: const Text('Aceptar convenio'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _review(false),
                    child: const Text('Rechazar con correcciones'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
