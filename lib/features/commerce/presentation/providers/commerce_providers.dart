import 'package:flutter_riverpod/flutter_riverpod.dart'; // Comparte consultas entre las pantallas del flujo comercial.
import '../../../auth/domain/entities/user_profile.dart'; // Representa clientes y asociados disponibles.
import '../../../auth/presentation/providers/auth_providers.dart'; // Reutiliza la sesión y el cliente configurados.
import '../../data/repositories/supabase_commerce_repository.dart'; // Implementa el acceso protegido a Supabase.
import '../../domain/entities/commerce_models.dart'; // Define las entidades mostradas por la interfaz.
import '../../domain/repositories/commerce_repository.dart'; // Permite sustituir la red en pruebas.

final commerceRepositoryProvider = Provider<CommerceRepository>(
  (ref) => SupabaseCommerceRepository(ref.watch(supabaseClientProvider)),
); // Mantiene un repositorio por sesión.
final freightRatesProvider = FutureProvider.autoDispose<List<FreightRate>>((
  ref,
) {
  ref.watch(authSessionProvider.select((state) => state.asData?.value.userId));
  return ref.watch(commerceRepositoryProvider).listRates();
}); // Actualiza el catálogo cuando cambia la cuenta.
final customerAccountsProvider = FutureProvider.autoDispose<List<UserProfile>>((
  ref,
) {
  ref.watch(currentUserProfileProvider);
  return ref.watch(commerceRepositoryProvider).listCustomers();
}); // Renueva las cuentas comerciales al cambiar los permisos.
final associationRequestsProvider =
    FutureProvider.autoDispose<List<AssociationRequest>>((ref) {
      ref.watch(currentUserProfileProvider);
      return ref.watch(commerceRepositoryProvider).listRequests();
    }); // Consulta las solicitudes autorizadas.
final agreementsProvider = FutureProvider.autoDispose<List<Agreement>>((ref) {
  ref.watch(currentUserProfileProvider);
  return ref.watch(commerceRepositoryProvider).listAgreements();
}); // Consulta los convenios aprobados.
final conversationsProvider =
    FutureProvider.autoDispose<List<SupportConversation>>((ref) {
      ref.watch(currentUserProfileProvider);
      return ref.watch(commerceRepositoryProvider).listConversations();
    }); // Comparte la bandeja y sus notificaciones.
final associationRequestProvider = FutureProvider.autoDispose
    .family<AssociationRequest, String>(
      (ref, id) => ref.watch(commerceRepositoryProvider).getRequest(id),
    ); // Consulta un expediente y sus documentos.
