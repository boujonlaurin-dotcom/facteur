import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Client HTTP de debug pour inspecter les requêtes Supabase
/// et forcer un User-Agent valide.
class DebugHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 1. Force User-Agent if needed
    if (!request.headers.containsKey('User-Agent')) {
      request.headers['User-Agent'] = 'Facteur/1.0.0 (Android; Release)';
    }

    // 2. Log Debug Info
    final method = request.method;
    final url = request.url;

    debugPrint('Supabase DEBUG: Request [$method] $url');
    debugPrint('Supabase DEBUG: Headers: ${request.headers}');

    try {
      final response = await _inner.send(request);

      debugPrint('Supabase DEBUG: Response Status: ${response.statusCode}');
      return response;
    } catch (e) {
      debugPrint('Supabase DEBUG: Network Error: $e');
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
