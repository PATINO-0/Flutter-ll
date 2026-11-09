import 'package:flutter_riverpod/flutter_riverpod.dart'; // Mantiene las consultas sincronizadas entre módulos.
import '../../auth/presentation/providers/auth_providers.dart'; // Renueva datos al cambiar la sesión o los permisos.
import '../data/supabase_coffee_exports_repository.dart'; // Implementa el acceso con políticas de Supabase.
import '../domain/coffee_exports_repository.dart'; // Permite probar las pantallas sin conexiones reales.
import '../domain/export_models.dart'; // Define los resultados de los proveedores.

final coffeeExportsRepositoryProvider = Provider<CoffeeExportsRepository>(
  (ref) => SupabaseCoffeeExportsRepository(ref.watch(supabaseClientProvider)),
);
final coffeeCultivationsProvider =
    FutureProvider.autoDispose<List<CoffeeCultivation>>((ref) {
      ref.watch(currentUserProfileProvider);
      return ref.watch(coffeeExportsRepositoryProvider).cultivations();
    }); // Consulta cultivos propios o todos para el personal.
final coffeeExportLotsProvider =
    FutureProvider.autoDispose<List<CoffeeExportLot>>((ref) {
      ref.watch(currentUserProfileProvider);
      return ref.watch(coffeeExportsRepositoryProvider).lots();
    }); // Incluye la reserva de cada lote.
final coffeeExportRequestsProvider =
    FutureProvider.autoDispose<List<CoffeeExportRequest>>((ref) {
      ref.watch(currentUserProfileProvider);
      return ref.watch(coffeeExportsRepositoryProvider).requests();
    });
final coffeeExportRequestProvider = FutureProvider.autoDispose
    .family<CoffeeExportRequest, String>(
      (ref, id) => ref.watch(coffeeExportsRepositoryProvider).request(id),
    );
final coffeeShipmentsProvider =
    FutureProvider.autoDispose<List<CoffeeShipment>>((ref) {
      ref.watch(currentUserProfileProvider);
      return ref.watch(coffeeExportsRepositoryProvider).shipments();
    });
final transportJobsProvider = FutureProvider.autoDispose<List<CoffeeShipment>>((
  ref,
) {
  ref.watch(currentUserProfileProvider);
  return ref.watch(coffeeExportsRepositoryProvider).transportJobs();
});
final transportersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      ref.watch(currentUserProfileProvider);
      return ref.watch(coffeeExportsRepositoryProvider).transporters();
    });
