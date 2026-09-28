import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_brand.dart';
import '../../../../shared/widgets/coming_soon_panel.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../widgets/dashboard_home.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() {
    return _DashboardPageState();
  }
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int _selectedIndex = 0;

  static const _sections = [
    _DashboardSection(
      title: 'Panel principal',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _DashboardSection(
      title: 'Café',
      icon: Icons.coffee_outlined,
      selectedIcon: Icons.coffee,
    ),
    _DashboardSection(
      title: 'Clientes',
      icon: Icons.business_outlined,
      selectedIcon: Icons.business,
    ),
    _DashboardSection(
      title: 'Exportaciones',
      icon: Icons.local_shipping_outlined,
      selectedIcon: Icons.local_shipping,
    ),
  ];

  Future<void> _logout() async {
    final errorMessage = await ref
        .read(authControllerProvider.notifier)
        .signOut();

    if (!mounted || errorMessage == null) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(errorMessage)));
  }

  void _selectSection(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildContent(String userName) {
    switch (_selectedIndex) {
      case 0:
        return DashboardHome(userName: userName);

      case 1:
        return const Padding(
          padding: EdgeInsets.all(24),
          child: ComingSoonPanel(
            title: 'Gestión de Café',
            description:
                'El registro, consulta, detalle y edición de café se implementarán en el Sprint 3.',
            icon: Icons.coffee_outlined,
          ),
        );

      case 2:
        return const Padding(
          padding: EdgeInsets.all(24),
          child: ComingSoonPanel(
            title: 'Gestión de Clientes',
            description:
                'El registro, consulta, detalle y edición de clientes se implementarán en el Sprint 3.',
            icon: Icons.business_outlined,
          ),
        );

      case 3:
        return const Padding(
          padding: EdgeInsets.all(24),
          child: ComingSoonPanel(
            title: 'Gestión de Exportaciones',
            description:
                'Las exportaciones, estados y documentos se implementarán en el Sprint 4.',
            icon: Icons.local_shipping_outlined,
          ),
        );

      default:
        return DashboardHome(userName: userName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final authState = ref.watch(authControllerProvider);
    final logoutLoading = authState.isLoading;

    final userName = profileAsync.when(
      data: (profile) {
        if (profile == null || profile.fullName.trim().isEmpty) {
          return 'Usuario';
        }

        return profile.fullName;
      },
      loading: () => 'Usuario',
      error: (_, _) => 'Usuario',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final isDesktop = constraints.maxWidth > 1024;

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(title: const AppBrand(compact: true)),
            drawer: Drawer(
              child: SafeArea(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: AppBrand(compact: true),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _sections.length,
                        itemBuilder: (context, index) {
                          final section = _sections[index];

                          return ListTile(
                            selected: _selectedIndex == index,
                            leading: Icon(
                              _selectedIndex == index
                                  ? section.selectedIcon
                                  : section.icon,
                            ),
                            title: Text(section.title),
                            onTap: () {
                              Navigator.of(context).pop();
                              _selectSection(index);
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: ListTile(
                        leading: logoutLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.logout),
                        title: const Text('Cerrar sesión'),
                        onTap: logoutLoading ? null : _logout,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: _buildContent(userName),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: isDesktop,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectSection,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: isDesktop
                        ? const SizedBox(
                            width: 210,
                            child: AppBrand(compact: true),
                          )
                        : Icon(
                            Icons.coffee,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: isDesktop
                            ? TextButton.icon(
                                onPressed: logoutLoading ? null : _logout,
                                icon: logoutLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.logout),
                                label: const Text('Cerrar sesión'),
                              )
                            : IconButton(
                                tooltip: 'Cerrar sesión',
                                onPressed: logoutLoading ? null : _logout,
                                icon: logoutLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.logout),
                              ),
                      ),
                    ),
                  ),
                  destinations: [
                    for (final section in _sections)
                      NavigationRailDestination(
                        icon: Icon(section.icon),
                        selectedIcon: Icon(section.selectedIcon),
                        label: Text(section.title),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildContent(userName)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardSection {
  const _DashboardSection({
    required this.title,
    required this.icon,
    required this.selectedIcon,
  });

  final String title;
  final IconData icon;
  final IconData selectedIcon;
}
