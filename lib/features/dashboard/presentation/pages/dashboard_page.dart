import 'dart:async'; // Actualiza permisos y avisos mientras el panel está abierto.
import 'package:flutter/material.dart'; // Construye el panel adaptable de la aplicación.
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Consulta la sesión y el perfil actual.
import 'package:go_router/go_router.dart'; // Abre la administración desde el panel principal.

import '../../../../core/constants/app_routes.dart'; // Comparte las rutas de navegación.
import '../../../../core/errors/app_exception.dart'; // Presenta los errores recuperables del perfil en español.
import '../../../../shared/widgets/app_brand.dart'; // Presenta la identidad de Ritech.
import '../../../auth/domain/entities/user_profile.dart'; // Determina las funciones disponibles por perfil.
import '../../../auth/presentation/providers/auth_providers.dart'; // Proporciona autenticación y roles.
import '../widgets/dashboard_home.dart'; // Presenta la bienvenida y los permisos del usuario.
import '../../../commerce/presentation/pages/store_page.dart'; // Presenta la tienda reservada al cliente y al administrador.
import '../../../commerce/presentation/pages/commerce_lists.dart'; // Integra clientes, solicitudes, convenios y atención.
import '../../../commerce/presentation/providers/commerce_providers.dart'; // Actualiza notificaciones y cambios de rol.
import '../../../exports/presentation/coffee_crops_page.dart'; // Presenta cultivos propios para asociados y el inventario completo al personal.
import '../../../exports/presentation/export_pages.dart'; // Separa solicitudes, seguimiento activo y entregas realizadas.
import '../../../exports/presentation/transport_pages.dart'; // Integra toma de cargas y coordinación con empleados.

/// Adapta las opciones de navegación a los roles asignados en el servidor.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

/// Mantiene la sección elegida sin conceder permisos a través de la interfaz.
class _DashboardPageState extends ConsumerState<DashboardPage>
    with WidgetsBindingObserver {
  String _selectedSection =
      'Panel principal'; // Conserva la selección aunque cambien los roles.
  Timer?
  _refreshTimer; // Mantiene visibles respuestas nuevas y promociones a asociado.

  /// Prepara las consultas y recursos locales al abrir la pantalla.
  @override
  void initState() {
    super.initState(); // Inicializa el estado visual del panel.
    WidgetsBinding.instance.addObserver(
      this,
    ); // Detecta cuándo el usuario vuelve a la aplicación.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        if (!ref.read(currentUserProfileProvider).isLoading) {
          ref.invalidate(currentUserProfileProvider);
        } // Espera una consulta pendiente en lugar de reiniciarla cada quince segundos.
        if (ref
                    .read(currentUserProfileProvider)
                    .asData
                    ?.value
                    ?.roles
                    .isNotEmpty ==
                true &&
            !ref.read(conversationsProvider).isLoading) {
          ref.invalidate(conversationsProvider);
        }
      }
    }); // La validación de permisos permanece siempre en el servidor.
  }

  /// Libera los controladores, suscripciones o temporizadores que conserva esta instancia.
  @override
  void dispose() {
    _refreshTimer?.cancel(); // No mantiene consultas cuando el panel se cierra.
    WidgetsBinding.instance.removeObserver(
      this,
    ); // Libera la observación del ciclo de vida.
    super.dispose(); // Completa la liberación del estado.
  }

  /// Vuelve a comprobar permisos al regresar al primer plano sin interrumpir una consulta pendiente.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!ref.read(currentUserProfileProvider).isLoading) {
        ref.invalidate(currentUserProfileProvider);
      } // Actualiza al volver sin interrumpir una comprobación que ya estaba en curso.
    }
  }

  /// Construye solamente las opciones que corresponden a las responsabilidades del perfil.
  List<_DashboardSection> _sectionsFor(UserProfile profile) {
    final conversations = profile.roles.isEmpty
        ? null
        : ref.watch(conversationsProvider).asData?.value;
    final supportUnread =
        conversations
            ?.where((item) => item.channel == 'support')
            .fold<int>(0, (count, item) => count + item.unreadCount) ??
        0;
    final exportUnread =
        conversations
            ?.where((item) => item.channel == 'exports')
            .fold<int>(0, (count, item) => count + item.unreadCount) ??
        0;
    final transportUnread =
        conversations
            ?.where((item) => item.channel == 'transport')
            .fold<int>(0, (count, item) => count + item.unreadCount) ??
        0; // Cada bandeja muestra solo sus propias notificaciones.
    if (profile.effectiveRole?.value == 'transporter') {
      return [
        _DashboardSection(
          'Envíos',
          Icons.local_shipping_outlined,
          exportUnread,
        ),
        _DashboardSection(
          'Chat de transporte',
          Icons.chat_outlined,
          transportUnread,
        ),
      ];
    } // El transportador no hereda los módulos del empleado.
    return [
      if (profile.canAccessCoffee)
        const _DashboardSection(
          'Panel principal',
          Icons.dashboard_outlined,
        ), // El cliente entra directamente a su tienda.
      if (profile.roles.isEmpty)
        const _DashboardSection('Sin acceso asignado', Icons.lock_outline),
      if (profile.canAccessStore)
        const _DashboardSection('Tienda', Icons.storefront_outlined),
      if (profile.effectiveRole?.value == 'client' ||
          profile.canManageOperations)
        const _DashboardSection('Solicitudes', Icons.assignment_outlined),
      if (profile.canCreateShipments)
        const _DashboardSection('Mis envíos', Icons.inventory_2_outlined),
      if (profile.canCreateShipments)
        const _DashboardSection('Seguimiento', Icons.location_on_outlined),
      if (profile.canManageAgreements)
        const _DashboardSection('Convenios', Icons.handshake_outlined),
      if (profile.canCreateShipments)
        const _DashboardSection('Exportaciones', Icons.local_shipping_outlined),
      if (profile.canAccessCoffee)
        const _DashboardSection('Café', Icons.coffee_outlined),
      if (profile.canManageOperations) ...[
        const _DashboardSection(
          'Clientes',
          Icons.business_outlined,
        ), // Reserva la gestión interna a trabajadores.
      ],
      if (profile.canCreateShipments)
        _DashboardSection(
          'Chat de Envíos',
          Icons.forum_outlined,
          exportUnread + transportUnread,
        ),
      if (profile.canManageOperations)
        const _DashboardSection(
          'Transportadores',
          Icons.airport_shuttle_outlined,
        ),
      if (profile.isAdmin)
        const _DashboardSection(
          'Operación de transporte',
          Icons.route_outlined,
        ),
      if (profile.roles.isNotEmpty)
        _DashboardSection(
          'Chat de atención',
          Icons.chat_outlined,
          supportUnread,
        ),
      if (profile.isAdmin)
        const _DashboardSection(
          'Administración de usuarios',
          Icons.admin_panel_settings_outlined,
        ),
    ];
  }

  /// Solicita el cierre de sesión y presenta los errores recuperables.
  Future<void> _logout() async {
    final message = await ref
        .read(authControllerProvider.notifier)
        .signOut(); // Cierra la sesión de Supabase.
    if (mounted && message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Mantiene la administración como una pantalla separada del contenido operativo.
  Future<void> _selectSection(_DashboardSection section) async {
    if (section.title == 'Administración de usuarios') {
      await context.push(
        AppRoutes.administration,
      ); // La ruta verifica nuevamente el rol en el servidor.
      if (mounted) {
        ref.invalidate(
          currentUserProfileProvider,
        ); // Actualiza el menú al regresar.
      }
      return; // Conserva la sección operativa anterior.
    }
    setState(
      () => _selectedSection = section.title,
    ); // Selecciona una sección permitida del panel.
  }

  /// Abre el módulo autorizado por la sección efectiva del usuario.
  Widget _buildContent(UserProfile profile, _DashboardSection section) {
    switch (section.title) {
      case 'Sin acceso asignado':
        return const Center(
          child: Text(
            'Todavía no tienes roles asignados. Contacta al administrador para solicitar acceso a los módulos.',
          ),
        );
      case 'Mis envíos':
        return const CoffeeShipmentHistoryPage();
      case 'Exportaciones':
        return const CoffeeExportsPage();
      case 'Seguimiento':
        return const CoffeeShipmentHistoryPage(tracking: true);
      case 'Café':
        return const CoffeeCropsPage();
      case 'Envíos':
      case 'Operación de transporte':
        return const TransportJobsPage();
      case 'Chat de transporte':
        return const SupportInboxPage(channel: 'transport');
      case 'Chat de Envíos':
        return const SupportInboxPage(channel: 'exports');
      case 'Transportadores':
        return const TransporterDirectoryPage();
      case 'Tienda':
        return const StorePage();
      case 'Solicitudes':
        return const AssociationRequestsPage();
      case 'Clientes':
        return const CustomerAccountsPage();
      case 'Convenios':
        return const AgreementsPage();
      case 'Chat de atención':
        return const SupportInboxPage();
    }
    return DashboardHome(
      profile: profile,
    ); // Conserva un panel válido cuando cambia la selección por una modificación de roles.
  }

  /// Construye la interfaz y observa únicamente los datos que necesita esta vista.
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(
      currentUserProfileProvider,
    ); // Consulta el perfil antes de mostrar funciones.
    final loading = ref
        .watch(authControllerProvider)
        .isLoading; // Evita cierres de sesión simultáneos.
    return profile.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => _buildProfileError(
        error is AppException
            ? error.userMessage
            : 'No fue posible cargar tu perfil. Intenta nuevamente.',
        loading,
      ),
      data: (user) {
        if (user == null) {
          return _buildProfileError(
            'Tu perfil no está disponible. Contacta al administrador.',
            loading,
          );
        }
        if (!user.isActive) {
          return _buildProfileError(
            'Tu acceso a Ritech fue retirado. Contacta al administrador.',
            loading,
          ); // Bloquea también las sesiones abiertas antes de la eliminación.
        }
        final sections = _sectionsFor(
          user,
        ); // Construye el menú con los roles recibidos del servidor.
        final foundIndex = sections.indexWhere(
          (section) => section.title == _selectedSection,
        ); // Busca la selección vigente.
        final selectedIndex = foundIndex < 0
            ? 0
            : foundIndex; // Vuelve al panel si un rol dejó de permitir la sección.
        final content = _buildContent(
          user,
          sections[selectedIndex],
        ); // Nunca muestra una sección retirada del menú.
        return LayoutBuilder(
          builder: (context, constraints) {
            final mobile =
                constraints.maxWidth < 600 ||
                constraints.maxHeight < sections.length * 56 + 160 ||
                sections.length <
                    2; // El menú lateral también admite cuentas sin módulos asignados.
            if (mobile) {
              return Scaffold(
                appBar: AppBar(
                  title: const AppBrand(compact: true),
                  actions: [
                    IconButton(
                      tooltip: 'Actualizar perfil y permisos',
                      onPressed: () =>
                          ref.invalidate(currentUserProfileProvider),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                drawer: Drawer(
                  child: SafeArea(
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: AppBrand(compact: true),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final section in sections)
                                ListTile(
                                  selected:
                                      section.title ==
                                      sections[selectedIndex]
                                          .title, // Señala la sección operativa actual.
                                  leading: Badge(
                                    isLabelVisible: section.unreadCount > 0,
                                    label: Text('${section.unreadCount}'),
                                    child: Icon(section.icon),
                                  ), // Señala también las solicitudes y respuestas sin leer.
                                  title: Text(
                                    section.title,
                                  ), // Presenta el módulo en español.
                                  onTap: () {
                                    Navigator.of(
                                      context,
                                    ).pop(); // Cierra el menú antes de navegar.
                                    _selectSection(
                                      section,
                                    ); // Abre únicamente una opción permitida.
                                  },
                                ),
                            ],
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('Cerrar sesión'),
                          onTap: loading ? null : _logout,
                        ),
                      ],
                    ),
                  ),
                ),
                body:
                    content, // Presenta el contenido permitido en el espacio principal.
              );
            }
            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    NavigationRail(
                      extended:
                          constraints.maxWidth >
                          1024, // Muestra etiquetas cuando hay espacio suficiente.
                      selectedIndex:
                          selectedIndex, // Señala la sección vigente del panel.
                      onDestinationSelected: (index) => _selectSection(
                        sections[index],
                      ), // Abre la opción elegida.
                      leading: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Ritech'),
                      ),
                      trailing: Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize
                                .min, // Agrupa las acciones al pie del menú.
                            children: [
                              IconButton(
                                tooltip: 'Actualizar perfil y permisos',
                                onPressed: () =>
                                    ref.invalidate(currentUserProfileProvider),
                                icon: const Icon(Icons.refresh),
                              ),
                              IconButton(
                                tooltip: 'Cerrar sesión',
                                onPressed: loading ? null : _logout,
                                icon: const Icon(Icons.logout),
                              ),
                            ],
                          ),
                        ),
                      ),
                      destinations: [
                        for (final section in sections)
                          NavigationRailDestination(
                            icon: Badge(
                              isLabelVisible: section.unreadCount > 0,
                              label: Text('${section.unreadCount}'),
                              child: Icon(section.icon),
                            ),
                            label: Text(section.title),
                          ),
                      ],
                    ),
                    const VerticalDivider(
                      width: 1,
                    ), // Separa visualmente navegación y contenido.
                    Expanded(
                      child: content,
                    ), // Aprovecha el ancho disponible para el módulo.
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Mantiene disponibles la recuperación y la salida cuando el perfil no se puede leer.
  Widget _buildProfileError(String message, bool loading) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(
            24,
          ), // Mantiene el mensaje legible en móvil.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
              ), // Explica por qué no se muestra el panel.
              TextButton(
                onPressed: () => ref.invalidate(currentUserProfileProvider),
                child: const Text('Reintentar'),
              ),
              TextButton(
                onPressed: loading ? null : _logout,
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Relaciona una opción del menú con su título e icono.
class _DashboardSection {
  const _DashboardSection(this.title, this.icon, [this.unreadCount = 0]);

  final String title; // Identifica la sección seleccionada y su texto visible.
  final IconData icon; // Representa el módulo en el menú adaptable.
  final int
  unreadCount; // Conserva el número de notificaciones del chat de atención.
}
