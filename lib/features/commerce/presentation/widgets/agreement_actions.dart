import 'package:flutter/material.dart'; // Recoge aceptación, motivo de cierre y vigencia con controles sencillos.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Renueva únicamente los datos afectados por la decisión.
import '../../../auth/presentation/providers/auth_providers.dart'; // Actualiza el rol después de aceptar o revocar.
import '../providers/commerce_providers.dart'; // Ejecuta los cambios transaccionales en Supabase.
import 'commerce_widgets.dart'; // Conserva el formulario ante errores recuperables.

/// Propone un año de vigencia al personal, conservando una fecha explícita en el expediente.
DateTime defaultAgreementExpiration() {
  final now = DateTime.now();
  return DateTime(now.year + 1, now.month, now.day, 23, 59, 59);
}

/// Presenta fechas legibles sin incorporar otra dependencia de formato.
String agreementDate(DateTime? value) => value == null
    ? 'Sin vencimiento registrado'
    : '${value.toLocal().day.toString().padLeft(2, '0')}/${value.toLocal().month.toString().padLeft(2, '0')}/${value.toLocal().year}';

/// Limita la vigencia a una fecha futura de hasta diez años, igual que el servidor.
Future<DateTime?> chooseAgreementExpiration(
  BuildContext context,
  DateTime current,
) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(now.year, now.month, now.day + 1),
    lastDate: DateTime(now.year + 10, now.month, now.day - 1),
    helpText: 'Vigencia del convenio',
    cancelText: 'Cancelar',
    confirmText: 'Elegir',
  );
  return date == null
      ? null
      : DateTime(date.year, date.month, date.day, 23, 59, 59);
}

/// Sincroniza expediente, cuentas, convenio, notificaciones y permisos después de una decisión confirmada.
void refreshAgreementViews(WidgetRef ref, String requestId) {
  ref.invalidate(associationRequestProvider(requestId));
  ref.invalidate(associationRequestsProvider);
  ref.invalidate(agreementsProvider);
  ref.invalidate(customerAccountsProvider);
  ref.invalidate(conversationsProvider);
  ref.invalidate(currentUserProfileProvider);
}

/// Exige aceptación expresa al titular o un motivo verificable al rechazar y revocar.
Future<void> showAgreementAction(
  BuildContext context,
  WidgetRef ref, {
  required String agreementId,
  required String requestId,
  required String action,
}) async {
  final accepting = action == 'accept';
  final revoking = action == 'revoke';
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  var consent = false;
  var busy = false;
  String? error;
  await showCommerceDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Text(
            accepting
                ? 'Aceptar convenio'
                : revoking
                ? 'Revocar convenio'
                : 'Rechazar propuesta',
          ),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (accepting)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: consent,
                      onChanged: busy
                          ? null
                          : (value) => setState(() => consent = value == true),
                      title: const Text(
                        'He revisado los documentos y la vigencia. Acepto el convenio y autorizo el tratamiento de mis datos para su ejecución.',
                      ),
                    ),
                  if (!accepting)
                    TextFormField(
                      controller: reason,
                      enabled: !busy,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        labelText: revoking
                            ? 'Motivo de revocación para el titular'
                            : 'Motivo del rechazo',
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 5
                          ? 'Explica el motivo con al menos 5 caracteres.'
                          : null,
                    ),
                  if (revoking)
                    const Text(
                      'El expediente y sus documentos se conservarán. El titular recibirá el motivo por el chat.',
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      if (accepting && !consent) {
                        setState(
                          () => error =
                              'Debes aceptar expresamente el convenio antes de continuar.',
                        );
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final repository = ref.read(commerceRepositoryProvider);
                        if (revoking) {
                          await repository.revokeAgreement(
                            agreementId,
                            reason.text,
                          );
                        } else {
                          await repository.respondToAgreement(
                            agreementId,
                            accept: accepting,
                            acceptedTerms: consent,
                            reason: reason.text,
                          );
                        }
                        if (dialogContext.mounted) {
                          refreshAgreementViews(ref, requestId);
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (problem) {
                        if (dialogContext.mounted) {
                          setState(() => error = problem.toString());
                        }
                      } finally {
                        if (dialogContext.mounted) setState(() => busy = false);
                      }
                    },
              child: Text(busy ? 'Guardando…' : 'Confirmar'),
            ),
          ],
        ),
      ),
    ),
  );
  reason
      .dispose(); // Espera la salida del diálogo antes de liberar el texto temporal.
}
