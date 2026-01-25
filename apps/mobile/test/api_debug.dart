import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://facteur-production.up.railway.app/api/',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    validateStatus: (status) => true,
  ));

  print('Testing API endpoints...');

  // Test 1: GET personalization/
  try {
    final response = await dio.get<dynamic>('users/personalization/');
    print('GET users/personalization/: ${response.statusCode}');
    if (response.statusCode != 200) {
      print('Response: ${response.data}');
    }
  } catch (e) {
    print('Error GET: $e');
  }

  // Test 2: POST mute-theme
  try {
    final response = await dio.post<dynamic>('users/personalization/mute-theme',
        data: {'theme': 'politics'});
    print('POST users/personalization/mute-theme: ${response.statusCode}');
    if (response.statusCode != 200) {
      print('Response: ${response.data}');
    }
  } catch (e) {
    print('Error POST: $e');
  }
}
