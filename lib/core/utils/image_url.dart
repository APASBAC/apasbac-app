/// Normaliza URLs de imagem vindas da API para que carreguem no Android.
///
/// - remove espaços e força HTTPS (o Android bloqueia HTTP em texto puro);
/// - converte links de compartilhamento do Google Drive em links diretos;
/// - pede ao Cloudinary uma versão JPG redimensionada. Fotos enviadas pelo
///   celular podem estar em HEIC ou ter vários MB, o que faz o
///   decodificador do Flutter falhar ou estourar memória.
String normalizeImageUrl(String? raw, {int width = 1080}) {
  var url = (raw ?? '').trim();
  if (url.isEmpty) return '';
  if (url.startsWith('//')) url = 'https:$url';
  if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
  if (!url.startsWith('https://')) return url;

  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  if (uri.host == 'drive.google.com') {
    final match = RegExp(r'/file/d/([^/]+)').firstMatch(uri.path);
    final id = match?.group(1) ?? uri.queryParameters['id'];
    if (id != null && id.isNotEmpty) {
      return 'https://drive.google.com/uc?export=view&id=$id';
    }
  }

  if (uri.host == 'res.cloudinary.com' && uri.path.contains('/image/upload/')) {
    const marker = '/image/upload/';
    final i = url.indexOf(marker) + marker.length;
    final rest = url.substring(i);
    // Já possui transformação explícita (ex.: "c_limit,w_800/"): mantém.
    final firstSegment = rest.split('/').first;
    if (RegExp(r'^[a-z]{1,3}_').hasMatch(firstSegment)) return url;
    return '${url.substring(0, i)}f_jpg,q_auto,c_limit,w_$width/$rest';
  }

  return url;
}

/// Garante HTTPS para URLs de vídeo (o Android bloqueia HTTP em texto puro).
String normalizeVideoUrl(String? raw) {
  var url = (raw ?? '').trim();
  if (url.startsWith('//')) url = 'https:$url';
  if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
  return url;
}

/// Imagem de capa de um vídeo do Cloudinary (quadro de 1 s, em JPG).
/// Retorna null para vídeos fora do Cloudinary.
String? videoPosterUrl(String? raw, {int width = 720}) {
  final url = normalizeVideoUrl(raw);
  const marker = '/video/upload/';
  if (!url.contains('res.cloudinary.com') || !url.contains(marker)) return null;
  final i = url.indexOf(marker) + marker.length;
  var rest = url.substring(i);
  final dot = rest.lastIndexOf('.');
  final slash = rest.lastIndexOf('/');
  if (dot > slash) rest = rest.substring(0, dot);
  return '${url.substring(0, i)}so_1,w_$width,c_limit,q_auto/$rest.jpg';
}
