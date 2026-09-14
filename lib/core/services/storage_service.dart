import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../api/api_client.dart';

/// Separate HTTP clients prevent the application's JWT reaching Cloudinary.
class StorageService {
  final Dio api;
  final Dio cloudinary;
  StorageService({Dio? api, Dio? cloudinary})
      : api = api ?? ApiClient().dio,
        cloudinary = cloudinary ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 3),
                sendTimeout: const Duration(minutes: 5)));

  Future<String> upload(XFile file,
      {required String folder,
      String resourceType = 'image',
      ProgressCallback? onProgress}) async {
    if (await file.length() == 0) throw ArgumentError('Arquivo vazio.');
    final response = await api.post('/storage/signed-upload', data: {
      'folder': folder,
      'resource_type': resourceType,
    });
    final body = response.data as Map;
    final signature = (body['data'] ?? body) as Map;
    final uri = Uri.parse(signature['upload_url'] as String);
    if (uri.scheme != 'https' || uri.host != 'api.cloudinary.com') {
      throw const FormatException('Endereço de upload inválido.');
    }
    final fields = Map<String, dynamic>.from(signature['form_fields'] as Map);
    final form = FormData.fromMap({
      for (final field in fields.entries) field.key: field.value.toString(),
      'file': MultipartFile.fromBytes(await file.readAsBytes(),
          filename: file.name),
    });
    final uploaded =
        await cloudinary.postUri(uri, data: form, onSendProgress: onProgress);
    final url = uploaded.data['secure_url'] as String?;
    if (url == null || Uri.tryParse(url)?.scheme != 'https') {
      throw const FormatException('O upload não retornou uma URL segura.');
    }
    return url;
  }
}
