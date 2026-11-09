import 'package:flutter/material.dart'; // Construye el catálogo de fletes y las condiciones de vinculación.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Consulta precios y permisos de edición.
import '../../../auth/presentation/providers/auth_providers.dart'; // Identifica a la cuenta que inicia el convenio.
import '../../domain/entities/commerce_models.dart'; // Representa las tarifas comerciales.
import '../providers/commerce_providers.dart'; // Proporciona el catálogo editable por administración.
import '../widgets/commerce_widgets.dart'; // Comparte mensajes y tratamiento de datos.
import 'association_form_page.dart'; // Inicia el formulario de solicitud del cliente.

/// Presenta tarifas, requisitos y el acceso a la solicitud de vinculación.
class StorePage extends ConsumerWidget {
  const StorePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    return CommerceSection(
      title: 'Tienda de servicios de importación',
      actions: [
        OutlinedButton(
          onPressed: () => ref.invalidate(freightRatesProvider),
          child: const Text('Actualizar tarifas'),
        ),
        if (profile?.isAdmin == true)
          FilledButton.icon(
            onPressed: () => _editRate(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Crear tarifa'),
          ),
      ],
      children: [
        Text(
          'Bienvenido, ${profile?.fullName ?? 'Usuario'}',
        ), // Personaliza la tienda sin mostrar módulos internos del personal.
        const Text(
          'Conoce los servicios y las condiciones para vincularte a Ritech. Para realizar operaciones de importación o exportación necesitas un convenio aprobado y el rol de asociado.',
        ),
        const SizedBox(height: 16),
        CommerceAsyncPanel(
          value: ref.watch(freightRatesProvider),
          onRetry: () => ref.invalidate(freightRatesProvider),
          builder: (List<FreightRate> items) => Column(
            children: [
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Estamos preparando las tarifas. Puedes consultar al equipo mediante el chat de atención.',
                  ),
                ),
              for (final rate in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          rate.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text('${rate.origin} → ${rate.destination}'),
                        Text(
                          '${rate.currency} ${rate.amount.toStringAsFixed(2)} / ${rate.unit}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(rate.description),
                        if (rate.isReference)
                          const Chip(
                            label: Text(
                              'Ejemplo de referencia · Solicita una cotización',
                            ),
                          ),
                        if (!rate.isActive) const Text('Tarifa desactivada'),
                        if (profile?.isAdmin == true)
                          TextButton(
                            onPressed: () => _editRate(context, ref, rate),
                            child: const Text('Editar tarifa'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Conviértete en asociado exportador',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Completa tus datos, adjunta tu identificación, una carta firmada de solicitud de convenio y un certificado tributario. El equipo revisará los documentos y te responderá por el chat.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: profile == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AssociationFormPage(customer: profile),
                  ),
                ),
          icon: const Icon(Icons.handshake_outlined),
          label: const Text('Quiero convertirme en asociado exportador'),
        ),
        TextButton.icon(
          onPressed: () => showDataProcessingNotice(context),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('Tratamiento de datos'),
        ),
      ],
    );
  }

  /// Permite a administración sustituir los ejemplos por tarifas comerciales verificadas.
  Future<void> _editRate(
    BuildContext context,
    WidgetRef ref, [
    FreightRate? rate,
  ]) async {
    final form = GlobalKey<FormState>();
    final title = TextEditingController(text: rate?.title);
    final origin = TextEditingController(text: rate?.origin);
    final destination = TextEditingController(text: rate?.destination);
    final amount = TextEditingController(text: rate?.amount.toString() ?? '');
    final unit = TextEditingController(text: rate?.unit ?? 'kg');
    final description = TextEditingController(text: rate?.description);
    var currency = rate?.currency ?? 'USD';
    var reference = rate?.isReference ?? true;
    var active = rate?.isActive ?? true;
    var busy = false;
    String? error;
    await showCommerceDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text(rate == null ? 'Crear tarifa' : 'Editar tarifa'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in [
                        (title, 'Servicio'),
                        (origin, 'Origen'),
                        (destination, 'Destino'),
                        (unit, 'Unidad'),
                        (description, 'Condiciones'),
                      ])
                        TextFormField(
                          controller: entry.$1,
                          enabled: !busy,
                          decoration: InputDecoration(labelText: entry.$2),
                          validator: (value) =>
                              (value?.trim().length ?? 0) <
                                  (entry.$1 == unit ? 1 : 3)
                              ? 'Completa este campo con información válida.'
                              : null,
                        ),
                      TextFormField(
                        controller: amount,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Precio por unidad',
                        ),
                        validator: (value) =>
                            (double.tryParse(
                                      value?.replaceAll(',', '.') ?? '',
                                    ) ??
                                    0) <=
                                0
                            ? 'Ingresa un precio mayor que cero.'
                            : null,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: currency,
                        items: ['USD', 'COP']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: busy ? null : (value) => currency = value!,
                        decoration: const InputDecoration(labelText: 'Moneda'),
                      ),
                      CheckboxListTile(
                        value: reference,
                        onChanged: busy
                            ? null
                            : (value) =>
                                  setState(() => reference = value == true),
                        title: const Text(
                          'Es una tarifa ilustrativa de referencia',
                        ),
                      ),
                      CheckboxListTile(
                        value: active,
                        onChanged: busy
                            ? null
                            : (value) => setState(() => active = value == true),
                        title: const Text('Mostrar en la tienda'),
                      ),
                      if (error != null) Text(error!),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await ref.read(commerceRepositoryProvider).saveRate({
                            if (rate != null) 'id': rate.id,
                            'title': title.text.trim(),
                            'origin': origin.text.trim(),
                            'destination': destination.text.trim(),
                            'amount': double.parse(
                              amount.text.replaceAll(',', '.'),
                            ),
                            'currency': currency,
                            'unit': unit.text.trim(),
                            'description': description.text.trim(),
                            'is_reference': reference,
                            'is_active': active,
                          });
                          if (context.mounted) {
                            ref.invalidate(freightRatesProvider);
                            Navigator.of(context).pop();
                          }
                        } catch (problem) {
                          if (context.mounted) {
                            setState(() => error = problem.toString());
                          }
                        } finally {
                          if (context.mounted) setState(() => busy = false);
                        }
                      },
                child: Text(busy ? 'Guardando…' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
    for (final controller in [
      title,
      origin,
      destination,
      amount,
      unit,
      description,
    ]) {
      controller.dispose();
    } // Libera los datos del editor de tarifas.
  }
}
