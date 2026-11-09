import 'package:flutter/material.dart'; // Construye el formulario de vinculación.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Accede al expediente y al repositorio comercial.
import 'package:file_picker/file_picker.dart'; // Permite seleccionar documentos desde el dispositivo.
import '../../../../core/errors/app_exception.dart'; // Presenta validaciones de documentos sin detalles técnicos.
import '../../../auth/domain/entities/user_profile.dart'; // Identifica al solicitante o al cliente elegido por el personal.
import '../../domain/entities/commerce_models.dart'; // Define el expediente y sus soportes obligatorios.
import '../providers/commerce_providers.dart'; // Comparte las consultas del módulo.
import '../widgets/commerce_widgets.dart'; // Reutiliza errores y el aviso de tratamiento de datos.
import 'support_chat_page.dart'; // Abre el canal donde se notificó la solicitud enviada.

/// Recoge los datos de un cliente y conserva su borrador al volver al formulario.
class AssociationFormPage extends ConsumerStatefulWidget {
  const AssociationFormPage({
    required this.customer,
    this.onBehalf = false,
    super.key,
  });
  final UserProfile
  customer; // Define la cuenta a la que pertenecerá el convenio.
  final bool
  onBehalf; // Identifica una solicitud preparada por el personal con autorización del cliente.
  @override
  ConsumerState<AssociationFormPage> createState() =>
      _AssociationFormPageState();
}

class _AssociationFormPageState extends ConsumerState<AssociationFormPage> {
  final _formKey =
      GlobalKey<
        FormState
      >(); // Agrupa las validaciones de los datos personales.
  final _name =
      TextEditingController(); // Conserva los nombres del solicitante.
  final _identity =
      TextEditingController(); // Conserva el número de identificación.
  final _phone = TextEditingController(); // Conserva el número de contacto.
  final _address =
      TextEditingController(); // Conserva la dirección del solicitante.
  final _business =
      TextEditingController(); // Conserva la descripción de su actividad comercial.
  AssociationRequest?
  _request; // Mantiene el identificador del borrador y sus documentos.
  String?
  _error; // Explica fallos de apertura o envío sin perder los campos escritos.
  bool _loading = true; // Espera la validación del plazo de solicitud.
  bool _busy =
      false; // Evita duplicar cargas o envíos mientras se confirma una operación.
  bool _consent =
      false; // La aceptación nunca aparece seleccionada por defecto.

  @override
  void initState() {
    super.initState();
    _loadDraft();
  } // Recupera o crea un borrador autorizado.

  @override
  void dispose() {
    for (final controller in [_name, _identity, _phone, _address, _business]) {
      controller.dispose();
    }
    super.dispose();
  } // Libera los datos temporales del formulario.

  Future<void> _loadDraft() async {
    setState(() {
      _loading = true;
      _error = null;
    }); // Permite reintentar si la apertura falla.
    try {
      final request = await ref
          .read(commerceRepositoryProvider)
          .startRequest(widget.customer.id);
      if (!mounted) return;
      _name.text = request.fullName.isEmpty
          ? widget.customer.fullName
          : request
                .fullName; // Recupera el nombre existente del perfil o del borrador.
      _identity.text = request.identityNumber;
      _phone.text = request.phone;
      _address.text = request.address;
      _business.text =
          request.businessDescription; // Recupera datos previamente guardados.
      setState(() => _request = request);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload(AgreementDocumentKind kind) async {
    if (_busy || _request == null) return;
    setState(
      () => _busy = true,
    ); // Impide abrir varios selectores o enviar mientras se guarda un soporte.
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      ); // Selecciona un solo documento con formatos limitados.
      if (file == null || !mounted) return;
      if ((await file.length() ?? 0) > 10 * 1024 * 1024) {
        throw const AppException(
          'El documento no puede superar 10 MB.',
        ); // Comprueba el tamaño antes de cargar el contenido en memoria.
      }
      final bytes = await file
          .readAsBytes(); // Lee los datos mediante la API multiplataforma del selector.
      if (!mounted) return;
      final repository = ref.read(commerceRepositoryProvider);
      await repository.attachDocument(
        _request!,
        kind,
        file.name,
        bytes,
      ); // El repositorio también verifica la cabecera real del archivo.
      final updated = await repository.getRequest(
        _request!.id,
      ); // Actualiza los soportes confirmados por el servidor.
      if (mounted) setState(() => _request = updated);
    } catch (error) {
      if (mounted) showCommerceError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _request == null || !_formKey.currentState!.validate()) return;
    if (!_consent) {
      setState(
        () => _error = 'Debes aceptar el tratamiento de datos antes de enviar.',
      );
      return;
    }
    if (_request!.documents.length != 3) {
      setState(() => _error = 'Adjunta los tres documentos obligatorios.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final chat = await ref
          .read(commerceRepositoryProvider)
          .submitRequest(
            _request!,
            fullName: _name.text,
            identityNumber: _identity.text,
            phone: _phone.text,
            address: _address.text,
            business: _business.text,
            consent: _consent,
          );
      if (!mounted) return;
      ref.invalidate(associationRequestsProvider);
      ref.invalidate(
        conversationsProvider,
      ); // Renueva el expediente y su notificación.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SupportChatPage(
            conversationId: chat,
            title: widget.onBehalf
                ? widget.customer.fullName
                : 'Atención Ritech',
          ),
        ),
      ); // Continúa la solicitud en el mismo canal de atención.
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? value, int minimum, int maximum) {
    final text = value?.trim() ?? '';
    return text.length < minimum || text.length > maximum
        ? 'Ingresa entre $minimum y $maximum caracteres.'
        : null;
  } // Mantiene visibles los límites que también valida el servidor.

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.onBehalf
              ? 'Crear convenio para cliente'
              : 'Quiero convertirme en asociado exportador',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _request == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error ?? 'No fue posible abrir el formulario.'),
                    TextButton(
                      onPressed: _loadDraft,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Completa tus datos y adjunta los tres soportes. El equipo revisará la solicitud y responderá por el chat interno.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          maxLength: 100,
                          validator: (value) => _required(value, 3, 100),
                          decoration: const InputDecoration(
                            labelText: 'Nombres y apellidos',
                          ),
                        ),
                        TextFormField(
                          controller: _identity,
                          enabled: !_busy,
                          maxLength: 25,
                          validator: (value) =>
                              RegExp(
                                r'^[0-9A-Za-z-]{5,25}$',
                              ).hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Ingresa una identificación válida (5 a 25 caracteres).',
                          decoration: const InputDecoration(
                            labelText: 'Cédula o identificación',
                          ),
                        ),
                        TextFormField(
                          controller: _phone,
                          enabled: !_busy,
                          keyboardType: TextInputType.phone,
                          maxLength: 25,
                          validator: (value) =>
                              RegExp(
                                r'^[+0-9 ()-]{7,25}$',
                              ).hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Ingresa un número de contacto válido.',
                          decoration: const InputDecoration(
                            labelText: 'Número de contacto',
                          ),
                        ),
                        TextFormField(
                          controller: _address,
                          enabled: !_busy,
                          maxLength: 250,
                          validator: (value) => _required(value, 5, 250),
                          decoration: const InputDecoration(
                            labelText: 'Dirección',
                          ),
                        ),
                        TextFormField(
                          controller: _business,
                          enabled: !_busy,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 2000,
                          validator: (value) => _required(value, 10, 2000),
                          decoration: const InputDecoration(
                            labelText:
                                'Actividad comercial y productos que deseas importar o exportar',
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Documentos obligatorios · PDF, JPG o PNG · Máximo 10 MB por archivo',
                        ),
                        for (final kind in AgreementDocumentKind.values)
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
                                        (document) =>
                                            document.kind == kind.value,
                                      ))
                                    Text('Adjunto: ${document.name}'),
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _upload(kind),
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text(
                                      'Adjuntar o reemplazar documento',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () => showDataProcessingNotice(context),
                          icon: const Icon(Icons.privacy_tip_outlined),
                          label: const Text('Tratamiento de datos'),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _consent,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _consent = value == true),
                          title: Text(
                            widget.onBehalf
                                ? 'Confirmo que cuento con autorización del cliente para remitir sus datos y documentos.'
                                : 'He leído y acepto el tratamiento de mis datos para tramitar esta solicitud.',
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
                          onPressed: _busy ? null : _submit,
                          child: Text(
                            _busy
                                ? 'Procesando…'
                                : 'Enviar solicitud y abrir chat',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Puedes enviar una solicitud cada 30 días. Si el equipo la rechaza, podrás corregirla y volver a enviarla inmediatamente.',
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
