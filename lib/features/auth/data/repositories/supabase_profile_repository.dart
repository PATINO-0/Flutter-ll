import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

class SupabaseProfileRepository implements ProfileRepository {
  const SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<UserProfile?> findById(String userId) async {
    try {
      final data = await _client
          .from('profiles')
          .select('id, full_name, email, created_at, updated_at')
          .eq('id', userId)
          .limit(1);

      if (data.isEmpty) {
        return null;
      }

      return UserProfile.fromMap(Map<String, dynamic>.from(data.first));
    } catch (_) {
      throw const AppException(
        'No fue posible cargar la información de tu perfil.',
      );
    }
  }
}
