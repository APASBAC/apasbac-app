import 'dart:io';

import 'package:apasbac_app/core/utils/friendly_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException http(int status, [Object? data]) => DioException(
    requestOptions: RequestOptions(path: '/x'),
    type: DioExceptionType.badResponse,
    response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: data));

void main() {
  test('sem internet (DNS falhou) vira mensagem simples, sem detalhes técnicos',
      () {
    final e = DioException.connectionError(
        requestOptions: RequestOptions(path: '/animals'),
        reason: "Failed host lookup: 'apasbac-api.vercel.app'",
        error: const SocketException(
            "Failed host lookup: 'apasbac-api.vercel.app'"));
    final f = describeError(e);
    expect(f.kind, ErrorKind.offline);
    expect(f.text,
        'Sem conexão com a internet. Verifique o Wi-Fi ou os dados móveis e tente de novo.');
    expect(f.text, isNot(contains('Dio')));
    expect(f.text, isNot(contains('vercel')));
  });

  test('tempo esgotado, servidor fora, sessão e permissão', () {
    expect(
        describeError(DioException(
                requestOptions: RequestOptions(),
                type: DioExceptionType.receiveTimeout))
            .kind,
        ErrorKind.timeout);
    expect(describeError(http(503)).kind, ErrorKind.server);
    expect(describeError(http(401)).title, 'Sua sessão expirou');
    expect(describeError(http(403)).kind, ErrorKind.permission);
    expect(describeError(http(426)).kind, ErrorKind.update);
    expect(describeError(http(429)).kind, ErrorKind.rateLimit);
  });

  test('mensagem da API em validação é mostrada', () {
    expect(
        friendlyMessage(http(400, {
          'message': ['E-mail já cadastrado']
        })),
        'Confira os dados. E-mail já cadastrado');
    expect(friendlyMessage(http(409, {'message': 'CPF já cadastrado'})),
        contains('CPF já cadastrado'));
  });

  test('erros comuns fora do Dio', () {
    expect(describeError(const SocketException('x')).kind, ErrorKind.offline);
    expect(describeError(StateError('Já está sendo enviado.')).message,
        'Já está sendo enviado.');
    expect(describeError(Exception('qualquer')).title, 'Algo deu errado');
  });
}
