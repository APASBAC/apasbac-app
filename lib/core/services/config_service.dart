import 'package:dio/dio.dart';
import '../api/api_client.dart';

class ConfigService {
  final Dio api;
  ConfigService({Dio? api}) : api = api ?? ApiClient().dio;

  Future<List<Map<String, dynamic>>> getConfigs() async {
    final response = await api.get('/configs');
    final body = response.data;
    final data = body is Map ? body['data'] : body;
    return (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static String? validate(String key, String value) {
    if (key == 'monitoring_period_value' &&
        (int.tryParse(value) == null || int.parse(value) <= 0)) {
      return 'Informe um número inteiro maior que zero.';
    }
    if (key == 'monitoring_period_unit' &&
        !['DAYS', 'WEEKS', 'MONTHS', 'YEARS'].contains(value)) {
      return 'Selecione uma unidade válida.';
    }
    if (key == 'apasbac_email' &&
        value.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return 'Informe um e-mail válido.';
    }
    if (key == 'apasbac_phone' &&
        value.isNotEmpty &&
        !RegExp(r'^\+?[\d\s()\-]{10,20}$').hasMatch(value)) {
      return 'Informe um telefone com DDD.';
    }
    return null;
  }

  Future<void> update(String key, String value, String description) async {
    final error = validate(key, value.trim());
    if (error != null) throw ArgumentError(error);
    await api.patch('/configs/${Uri.encodeComponent(key)}', data: {
      'value': value.trim(),
      'description': description.trim(),
    });
  }
}
