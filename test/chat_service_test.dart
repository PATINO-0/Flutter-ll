import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riexport_ue/features/commerce/data/repositories/supabase_commerce_repository.dart';

void main() {
  for (final status in [200, 204]) {
    test(
      'El chat acepta respuesta vacía $status y conserva tildes y emoji',
      () async {
        final client = SupabaseClient(
          'https://test.supabase.co',
          'test-key',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/rest/v1/rpc/send_chat_message');
            final payload = jsonDecode(utf8.decode(request.bodyBytes)) as Map;
            expect(payload['message_body'], 'Café listo ☕');
            expect(payload['target_conversation'], 'conversation-demo');
            return http.Response('', status, request: request);
          }),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        addTearDown(client.dispose);
        await SupabaseCommerceRepository(
          client,
        ).sendMessage('conversation-demo', '  Café listo ☕  ');
      },
    );
  }
}
