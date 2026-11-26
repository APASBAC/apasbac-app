import 'dart:typed_data';

import 'package:apasbac_app/core/services/capture_attestation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('assinatura igual à da API (referência calculada com Node/crypto)', () {
    expect(
        captureSignature(
            'chave-teste',
            'video',
            '0cc175b9c0f1b6a831c399e269772661',
            '2026-11-26T12:00:00.000Z',
            'm1'),
        'a8e63d191f4090a4dec8dc918921e56e2ccb347355fe7a5db0c3499f736fa533');
  });

  test(
      'atestado: MD5 do conteúdo, horário em UTC com milissegundos e assinatura',
      () async {
    final session = CaptureSession(
        monitoringId: 'm1',
        token: 't',
        key: 'chave-teste',
        expiresAt: DateTime.utc(2100));
    final c = await attestCapture(
        XFile.fromData(Uint8List.fromList('a'.codeUnits), name: 'v.mp4'),
        kind: 'video',
        session: session,
        now: DateTime.utc(2026, 11, 26, 12));
    expect(c.proof.md5, '0cc175b9c0f1b6a831c399e269772661');
    expect(c.proof.capturedAt, '2026-11-26T12:00:00.000Z');
    expect(c.proof.signature,
        'a8e63d191f4090a4dec8dc918921e56e2ccb347355fe7a5db0c3499f736fa533');
    expect(c.proof.forUrl('https://x/v.mp4')['url'], 'https://x/v.mp4');
  });
}
