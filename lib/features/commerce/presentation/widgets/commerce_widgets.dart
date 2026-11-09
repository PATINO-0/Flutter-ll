import 'package:flutter/material.dart'; // Construye componentes comunes del flujo comercial.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Presenta resultados asíncronos sin duplicar estados.
import '../../../../core/errors/app_exception.dart'; // Muestra solo mensajes de error preparados para el usuario.

/// Mantiene consistentes los estados de carga, error y recuperación.
class CommerceAsyncPanel<T> extends StatelessWidget {
  const CommerceAsyncPanel({
    required this.value,
    required this.onRetry,
    required this.builder,
    super.key,
  });
  final AsyncValue<T> value; // Contiene los datos o el fallo de la consulta.
  final VoidCallback
  onRetry; // Permite recuperar la consulta sin cerrar la pantalla.
  final Widget Function(T data)
  builder; // Construye únicamente contenido disponible.
  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    ),
    error: (error, _) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error is AppException
                ? error.userMessage
                : 'No fue posible cargar la información.',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ), // Conserva una salida recuperable ante errores de conexión.
        ],
      ),
    ),
    data: builder,
  );
}

/// Organiza una sección adaptable dentro del dashboard.
class CommerceSection extends StatelessWidget {
  const CommerceSection({
    required this.title,
    required this.children,
    this.actions = const [],
    super.key,
  });
  final String title; // Identifica la función del módulo.
  final List<Widget> children; // Contiene tarjetas y formularios del módulo.
  final List<Widget>
  actions; // Presenta las operaciones disponibles para el rol actual.
  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Wrap(spacing: 12, runSpacing: 8, children: actions),
              ),
            const SizedBox(height: 12),
            ...children, // Conserva espacio legible en pantallas pequeñas.
          ],
        ),
      ),
    ),
  );
}

/// Presenta un error de una acción conservando la pantalla y sus datos.
void showCommerceError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is AppException
            ? error.userMessage
            : 'No fue posible completar la operación.',
      ),
    ),
  );
}

/// Espera también la animación de salida antes de liberar controladores locales de un diálogo.
Future<T?> showCommerceDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  ); // Conserva el ciclo de vida real del contenido del formulario.
  final result = await Navigator.of(
    context,
    rootNavigator: true,
  ).push<T>(route); // Recupera la decisión del usuario.
  await route
      .completed; // Evita reconstruir campos cuyos controladores ya fueron liberados.
  return result;
}

/// Publica la explicación operativa que el solicitante debe aceptar explícitamente.
Future<void> showDataProcessingNotice(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Tratamiento de datos personales'),
    content: const SingleChildScrollView(
      child: Text(
        'Autorizo a Ritech a utilizar mi identificación, datos de contacto y documentos para verificar mi solicitud, formalizar el convenio y atender mis consultas.\n\nEl expediente estará disponible para el personal autorizado y para mí. Los documentos se almacenan de forma privada. Puedo solicitar la consulta, actualización o eliminación de mis datos mediante el chat de atención; los soportes necesarios del convenio podrán conservarse como parte de su historial.\n\nEsta autorización se registra al enviar la solicitud. Versión: 2026-11-08-v1.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Entendido'),
      ),
    ],
  ),
);
