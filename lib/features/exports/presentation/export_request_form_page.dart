import 'package:file_picker/file_picker.dart'; // Selecciona los soportes de la exportación.
import 'package:flutter/material.dart'; // Construye el formulario y las autorizaciones.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte el expediente con los módulos relacionados.
import '../../../core/errors/app_exception.dart'; // Presenta validaciones traducidas para el usuario.
import '../../commerce/presentation/pages/support_chat_page.dart'; // Continúa la solicitud en el chat alterno de envíos.
import '../../commerce/presentation/providers/commerce_providers.dart'; // Actualiza la notificación que recibe el personal.
import '../../commerce/presentation/widgets/commerce_widgets.dart'; // Reutiliza avisos y errores recuperables.
import '../domain/export_models.dart'; // Define cotización, solicitud y soportes.
import 'export_providers.dart'; // Delega permisos y cálculos en Supabase.
import '../../commerce/domain/entities/commerce_models.dart'; // Comparte las rutas habilitadas de la tienda.

/// Solicita una exportación desde un lote registrado, sin crear un envío antes de la revisión.
class ExportRequestFormPage extends ConsumerStatefulWidget {
  const ExportRequestFormPage({required this.lotId, super.key});
  final String
  lotId; // Identifica el lote que el servidor reservará una sola vez.
  @override
  ConsumerState<ExportRequestFormPage> createState() =>
      _ExportRequestFormPageState();
}

class _ExportRequestFormPageState extends ConsumerState<ExportRequestFormPage> {
  final _form =
      GlobalKey<
        FormState
      >(); // Agrupa la validación de recogida, entrega y contacto.
  final _origin =
      TextEditingController(); // Conserva municipio y dirección de recogida.
  final _destination =
      TextEditingController(); // Conserva ciudad, país y dirección de entrega.
  final _recipient =
      TextEditingController(); // Identifica quién recibirá el café.
  final _phone =
      TextEditingController(); // Conserva el contacto para la entrega.
  CoffeeExportRequest?
  _request; // Mantiene el borrador confirmado por el servidor.
  ExportQuote? _quote; // Conserva el costo que el asociado debe autorizar.
  List<FreightRate> _rates =
      []; // Excluye rutas desactivadas y servicios por volumen.
  String? _routeOrigin; // Limita el origen a los lugares del catálogo.
  String?
  _routeDestination; // Limita el destino a las conexiones del origen elegido.
  String?
  _rateId; // Distingue servicios con precios diferentes en una misma ruta.
  String? _error; // Permite corregir fallos sin perder los datos ingresados.
  bool _loading = true; // Espera la reserva del lote y la cotización.
  bool _busy = false; // Impide cargas y envíos simultáneos.
  bool _charge = false; // La autorización económica siempre empieza desmarcada.
  bool _data =
      false; // La autorización para gestionar los documentos es explícita.
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_origin, _destination, _recipient, _phone]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(coffeeExportsRepositoryProvider);
      final request = await repository.start(widget.lotId);
      final rates = (await repository.exportRates())
          .where((rate) => rate.isCoffeeExportAvailable)
          .toList();
      final previous = rates
          .where((rate) => rate.id == request.freightRateId)
          .firstOrNull;
      final quote = previous == null
          ? null
          : await repository.quote(request.id, previous.id);
      if (quote != null &&
          (quote.origin != previous!.origin ||
              quote.destination != previous.destination)) {
        throw const AppException(
          'La ruta cambió durante la consulta. Actualiza las rutas y tarifas.',
        );
      }
      if (!mounted) return;
      _origin.text = request.pickupAddress;
      _destination.text = request.deliveryAddress;
      _recipient.text = request.recipient;
      _phone.text = request.phone;
      setState(() {
        _request = request;
        _quote = quote;
        _rates = rates;
        _rateId = previous?.id;
        _routeOrigin = previous?.origin;
        _routeDestination = previous?.destination;
        _charge = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshQuote() async {
    if (_busy || _request == null) return;
    setState(() {
      _busy = true;
      _charge = false;
      _quote = null;
    }); // Cualquier cambio exige una nueva autorización del importe.
    try {
      final repository = ref.read(coffeeExportsRepositoryProvider);
      final rates = (await repository.exportRates())
          .where((rate) => rate.isCoffeeExportAvailable)
          .toList();
      if (!mounted) return;
      final selected = rates.where((rate) => rate.id == _rateId).firstOrNull;
      setState(() {
        _rates = rates;
        if (_routeOrigin != selected?.origin) _origin.clear();
        if (_routeDestination != selected?.destination) _destination.clear();
        _rateId = selected?.id;
        _routeOrigin = selected?.origin;
        _routeDestination = selected?.destination;
      });
      final quote = selected == null
          ? null
          : await repository.quote(_request!.id, selected.id);
      if (quote != null &&
          (quote.origin != selected!.origin ||
              quote.destination != selected.destination)) {
        throw const AppException(
          'La ruta cambió durante la consulta. Actualiza las rutas y tarifas.',
        );
      }
      if (mounted) {
        setState(() {
          _quote = quote;
          _charge = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectOrigin(String? value) {
    setState(() {
      _routeOrigin = value;
      _routeDestination = null;
      _rateId = null;
      _quote = null;
      _charge = false;
      _origin.clear();
      _destination.clear();
    }); // No conserva un destino ni una autorización de otra ruta.
  }

  Future<void> _selectDestination(String? value) async {
    if (value == null) return;
    setState(() {
      _routeDestination = value;
      _destination.clear();
      _rateId = _rates
          .firstWhere(
            (rate) => rate.origin == _routeOrigin && rate.destination == value,
          )
          .id;
    });
    await _refreshQuote();
  }

  Future<void> _upload(ExportDocumentKind kind) async {
    if (_busy || _request == null) return;
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (file == null || !mounted) return;
      if ((await file.length() ?? 0) > 10 * 1024 * 1024) {
        throw const AppException('El documento no puede superar 10 MB.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final repository = ref.read(coffeeExportsRepositoryProvider);
      await repository.attach(_request!, kind, file.name, bytes);
      final updated = await repository.request(_request!.id);
      if (mounted) setState(() => _request = updated);
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy ||
        _request == null ||
        _quote == null ||
        !_form.currentState!.validate()) {
      return;
    }
    if (!_charge || !_data) {
      setState(
        () => _error =
            'Autoriza el cargo calculado y el tratamiento de datos antes de enviar.',
      );
      return;
    }
    if (_request!.documents.length != 3) {
      setState(
        () => _error =
            'Adjunta factura comercial, lista de empaque y ficha de calidad.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(coffeeExportsRepositoryProvider)
          .submit(
            _request!,
            _quote!,
            origin: _origin.text,
            destination: _destination.text,
            recipient: _recipient.text,
            phone: _phone.text,
            authorizeCharge: _charge,
            authorizeData: _data,
          );
      if (!mounted) return;
      ref.invalidate(coffeeExportRequestsProvider);
      ref.invalidate(coffeeExportLotsProvider);
      ref.invalidate(conversationsProvider);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SupportChatPage(
            conversationId: id,
            title: 'Envíos · ${_request!.label}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _text(String? value, int minimum) =>
      (value?.trim().length ?? 0) < minimum
      ? 'Completa este campo con al menos $minimum caracteres.'
      : null;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Solicitar exportación de café')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _request == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error ?? 'No fue posible abrir la solicitud.'),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : _rates.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No hay rutas y tarifas habilitadas para exportar café. Contacta al equipo de atención.',
                    ),
                    TextButton(
                      onPressed: _busy ? null : _refreshQuote,
                      child: const Text('Actualizar rutas y tarifas'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 730),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${_request!.label} · Lote ${_request!.snapshot['lot_code'] ?? ''}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text(
                          'El personal revisará los documentos. Un lote aprobado no puede exportarse nuevamente. Si se rechaza, podrás corregir esta información y los soportes del mismo lote.',
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey('origin-$_routeOrigin'),
                          initialValue: _routeOrigin,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Origen habilitado',
                          ),
                          items: _rates
                              .map((rate) => rate.origin)
                              .toSet()
                              .map(
                                (origin) => DropdownMenuItem(
                                  value: origin,
                                  child: Text(origin),
                                ),
                              )
                              .toList(),
                          onChanged: _busy ? null : _selectOrigin,
                          validator: (value) => value == null
                              ? 'Selecciona un origen de la tienda.'
                              : null,
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'destination-$_routeOrigin-$_routeDestination',
                          ),
                          initialValue: _routeDestination,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Destino habilitado',
                          ),
                          items: _rates
                              .where((rate) => rate.origin == _routeOrigin)
                              .map((rate) => rate.destination)
                              .toSet()
                              .map(
                                (destination) => DropdownMenuItem(
                                  value: destination,
                                  child: Text(destination),
                                ),
                              )
                              .toList(),
                          onChanged: _busy || _routeOrigin == null
                              ? null
                              : _selectDestination,
                          validator: (value) => value == null
                              ? 'Selecciona un destino disponible para ese origen.'
                              : null,
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey('tariff-$_rateId'),
                          initialValue: _rateId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tarifa de la ruta',
                          ),
                          items: _rates
                              .where(
                                (rate) =>
                                    rate.origin == _routeOrigin &&
                                    rate.destination == _routeDestination,
                              )
                              .map(
                                (rate) => DropdownMenuItem(
                                  value: rate.id,
                                  child: Text(
                                    '${rate.title} · ${rate.currency} ${rate.amount.toStringAsFixed(2)}/kg',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _busy || _routeDestination == null
                              ? null
                              : (value) async {
                                  setState(() => _rateId = value);
                                  await _refreshQuote();
                                },
                          validator: (value) => value == null
                              ? 'Selecciona una tarifa habilitada.'
                              : null,
                        ),
                        TextButton(
                          onPressed: _busy ? null : _refreshQuote,
                          child: const Text('Actualizar rutas y tarifas'),
                        ),
                        TextFormField(
                          controller: _origin,
                          enabled: !_busy,
                          maxLength: 250,
                          decoration: const InputDecoration(
                            labelText:
                                'Dirección de recogida en el origen seleccionado',
                          ),
                          validator: (value) => _text(value, 5),
                        ),
                        TextFormField(
                          controller: _destination,
                          enabled: !_busy,
                          maxLength: 250,
                          decoration: const InputDecoration(
                            labelText:
                                'Dirección de entrega en el destino seleccionado',
                          ),
                          validator: (value) => _text(value, 5),
                        ),
                        TextFormField(
                          controller: _recipient,
                          enabled: !_busy,
                          maxLength: 150,
                          decoration: const InputDecoration(
                            labelText: 'Nombre del destinatario',
                          ),
                          validator: (value) => _text(value, 3),
                        ),
                        TextFormField(
                          controller: _phone,
                          enabled: !_busy,
                          maxLength: 25,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono del destinatario',
                          ),
                          validator: (value) {
                            final digits = (value ?? '').replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            return digits.length < 7 || digits.length > 15
                                ? 'Ingresa un teléfono con 7 a 15 dígitos.'
                                : null;
                          },
                        ),
                        if (_quote != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Costo calculado por peso',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    '${_quote!.title}\n${_quote!.origin} → ${_quote!.destination}\n${_quote!.description}',
                                  ),
                                  Text(
                                    '${_quote!.weight.toStringAsFixed(2)} kg × ${_quote!.currency} ${_quote!.rate.toStringAsFixed(2)} / kg',
                                  ),
                                  Text(
                                    'Total: ${_quote!.currency} ${_quote!.total.toStringAsFixed(2)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  if (_quote!.isReference)
                                    const Text(
                                      'Tarifa ilustrativa configurada por administración. Revisa el importe antes de autorizar.',
                                    ),
                                  TextButton(
                                    onPressed: _busy ? null : _refreshQuote,
                                    child: const Text('Actualizar cotización'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        for (final kind in ExportDocumentKind.values)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    kind.label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(kind.instructions),
                                  for (final document
                                      in _request!.documents.where(
                                        (item) => item.kind == kind.value,
                                      ))
                                    Text('Adjunto: ${document.name}'),
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _upload(kind),
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text(
                                      'Adjuntar o corregir documento',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const Text(
                          'Se aceptan PDF, JPG o PNG de hasta 10 MB por documento. Los soportes conservados de un rechazo pueden reemplazarse antes de volver a enviar.',
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _charge,
                          onChanged: _busy || _quote == null
                              ? null
                              : (value) =>
                                    setState(() => _charge = value == true),
                          title: _quote == null
                              ? const Text(
                                  'Selecciona una ruta y tarifa para autorizar el cargo.',
                                )
                              : Text(
                                  'Autorizo registrar un cargo de ${_quote!.currency} ${_quote!.total.toStringAsFixed(2)} en mi cuenta Ritech si la exportación es aceptada.',
                                ),
                        ),
                        TextButton.icon(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text(
                                'Tratamiento de datos de exportación',
                              ),
                              content: const SingleChildScrollView(
                                child: Text(
                                  'Autorizo a Ritech a utilizar mis documentos, datos del lote, recogida, destinatario y teléfono para revisar la exportación, gestionar el cargo autorizado y coordinar su entrega. El personal autorizado revisará los soportes. El transportador asignado recibirá los datos operativos necesarios para transportar y entregar el café, sin acceso a facturas ni autorización de cobro. Puedo solicitar la actualización de mis datos por el chat de atención. Versión: coffee-export-2026-11-08-v1.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Entendido'),
                                ),
                              ],
                            ),
                          ),
                          icon: const Icon(Icons.privacy_tip_outlined),
                          label: const Text('Tratamiento de datos'),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _data,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _data = value == true),
                          title: const Text(
                            'He leído y autorizo el tratamiento de datos para esta exportación y su entrega.',
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: _busy || _quote == null ? null : _submit,
                          child: Text(
                            _busy
                                ? 'Procesando…'
                                : 'Enviar solicitud al chat de Envíos',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}
