import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';

/// Sessão de captura entregue pela API (POST /monitoring/:id/capture-session).
class CaptureSession {
  final String monitoringId;
  final String token;
  final String key;
  final DateTime expiresAt;
  const CaptureSession(
      {required this.monitoringId,
      required this.token,
      required this.key,
      required this.expiresAt});

  factory CaptureSession.fromJson(
          String monitoringId, Map<String, dynamic> j) =>
      CaptureSession(
        monitoringId: monitoringId,
        token: j['captureToken'] as String,
        key: j['captureKey'] as String,
        expiresAt: DateTime.tryParse('${j['expiresAt']}') ??
            DateTime.now().add(const Duration(hours: 23)),
      );

  bool get expired => DateTime.now().isAfter(expiresAt);
}

/// Atestado de uma foto/vídeo gravado pela câmera do app.
class CaptureProof {
  final String kind; // 'image' | 'video'
  final String md5;
  final String capturedAt;
  final String signature;
  const CaptureProof(
      {required this.kind,
      required this.md5,
      required this.capturedAt,
      required this.signature});

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'md5': md5,
        'capturedAt': capturedAt,
        'signature': signature
      };

  factory CaptureProof.fromJson(Map<String, dynamic> j) => CaptureProof(
        kind: j['kind'] as String,
        md5: j['md5'] as String,
        capturedAt: j['capturedAt'] as String,
        signature: j['signature'] as String,
      );

  /// Item do campo `media` do envio.
  Map<String, dynamic> forUrl(String url) => {'url': url, ...toJson()};
}

/// Foto ou vídeo gravado pela câmera, já assinado.
class CapturedFile {
  final XFile file;
  final CaptureProof proof;
  const CapturedFile(this.file, this.proof);
}

/// HMAC-SHA256(chave, "kind|md5|capturedAt|monitoringId"), igual à API.
String captureSignature(String key, String kind, String md5Hex,
        String capturedAt, String monitoringId) =>
    Hmac(sha256, utf8.encode(key))
        .convert(utf8.encode('$kind|$md5Hex|$capturedAt|$monitoringId'))
        .toString();

/// Liga o arquivo gravado (md5) ao etag que o Cloudinary devolveu no upload:
/// HMAC-SHA256(chave, "upload|md5|etag|url|monitoringId"), igual à API.
String uploadSignature(String key, String md5Hex, String etag, String url,
        String monitoringId) =>
    Hmac(sha256, utf8.encode(key))
        .convert(utf8.encode('upload|$md5Hex|$etag|$url|$monitoringId'))
        .toString();

/// Assina o arquivo logo após a captura: MD5 do conteúdo (lido em fluxo, sem
/// carregar o vídeo inteiro na memória) + horário + chave da sessão.
Future<CapturedFile> attestCapture(XFile file,
    {required String kind,
    required CaptureSession session,
    DateTime? now}) async {
  final digest = await md5.bind(file.openRead()).first;
  final at = DateTime.fromMillisecondsSinceEpoch(
          (now ?? DateTime.now()).millisecondsSinceEpoch,
          isUtc: true)
      .toIso8601String();
  final hex = digest.toString();
  return CapturedFile(
    file,
    CaptureProof(
      kind: kind,
      md5: hex,
      capturedAt: at,
      signature:
          captureSignature(session.key, kind, hex, at, session.monitoringId),
    ),
  );
}
