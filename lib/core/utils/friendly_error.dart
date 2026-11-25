import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Tipo do problema, para escolher ícone e texto.
enum ErrorKind {
  offline,
  timeout,
  server,
  session,
  permission,
  notFound,
  tooLarge,
  rateLimit,
  update,
  validation,
  unknown
}

/// Erro em linguagem simples para mostrar na tela.
class FriendlyError {
  final ErrorKind kind;
  final String title;
  final String message;
  const FriendlyError(this.kind, this.title, this.message);

  /// Frase única (título + orientação) para avisos curtos e campos de erro.
  String get text => '$title. $message';
}

const _offline = FriendlyError(ErrorKind.offline, 'Sem conexão com a internet',
    'Verifique o Wi-Fi ou os dados móveis e tente de novo.');
const _timeout = FriendlyError(ErrorKind.timeout, 'A conexão está lenta',
    'O servidor demorou para responder. Tente de novo em instantes.');
const _server = FriendlyError(
    ErrorKind.server,
    'O servidor está com instabilidade',
    'Não é um problema no seu celular. Tente de novo em alguns minutos.');
const _unknown = FriendlyError(ErrorKind.unknown, 'Algo deu errado',
    'Tente de novo. Se continuar, avise a APASBAC.');

String? _apiText(dynamic data) {
  final msg = data is Map ? data['message'] : null;
  if (msg is List && msg.isNotEmpty) return msg.map((m) => '$m').join('\n');
  if (msg is String && msg.trim().isNotEmpty) return msg.trim();
  return null;
}

/// Traduz qualquer erro (Dio, rede, validação) para uma mensagem clara.
/// Detalhes técnicos vão só para o log, nunca para a tela.
FriendlyError describeError(Object error) {
  debugPrint('[erro] $error');
  if (error is FriendlyError) return error;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _timeout;
      case DioExceptionType.connectionError:
        return _offline;
      case DioExceptionType.badCertificate:
        return const FriendlyError(ErrorKind.offline, 'Conexão não segura',
            'A rede que você está usando bloqueou o acesso. Tente outra rede.');
      case DioExceptionType.cancel:
        return const FriendlyError(ErrorKind.unknown, 'Operação cancelada',
            'Tente de novo quando quiser.');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }
    final inner = error.error;
    if (error.response == null) {
      if (inner is SocketException || inner is HttpException) return _offline;
      if (inner is TimeoutException) return _timeout;
      if (inner != null && inner is! DioException) return describeError(inner);
      return _offline;
    }
    final status = error.response!.statusCode ?? 0;
    final api = _apiText(error.response!.data);
    if (status == 401) {
      return const FriendlyError(ErrorKind.session, 'Sua sessão expirou',
          'Entre novamente para continuar.');
    }
    if (status == 403) {
      return FriendlyError(ErrorKind.permission, 'Acesso não permitido',
          api ?? 'Sua conta não tem permissão para fazer isso.');
    }
    if (status == 404) {
      return FriendlyError(ErrorKind.notFound, 'Não encontrado',
          api ?? 'Este item não existe mais ou foi removido.');
    }
    if (status == 413) {
      return const FriendlyError(ErrorKind.tooLarge, 'Arquivo grande demais',
          'Escolha um vídeo mais curto ou fotos menores.');
    }
    if (status == 426) {
      return const FriendlyError(ErrorKind.update, 'Atualize o aplicativo',
          'Esta versão não é mais aceita. Instale a atualização para continuar.');
    }
    if (status == 429) {
      return const FriendlyError(ErrorKind.rateLimit,
          'Muitas tentativas seguidas', 'Espere um minuto e tente de novo.');
    }
    if (status >= 500) return _server;
    if (status >= 400) {
      return FriendlyError(ErrorKind.validation, 'Confira os dados',
          api ?? 'Algumas informações não foram aceitas.');
    }
    return _unknown;
  }
  if (error is SocketException || error is HttpException) return _offline;
  if (error is TimeoutException) return _timeout;
  if (error is FileSystemException) {
    return const FriendlyError(ErrorKind.unknown, 'Arquivo indisponível',
        'Não foi possível ler o arquivo no celular. Selecione de novo.');
  }
  if (error is FormatException) {
    return const FriendlyError(ErrorKind.server,
        'Resposta inesperada do servidor', 'Tente de novo em instantes.');
  }
  if (error is StateError) {
    return FriendlyError(
        ErrorKind.validation, 'Não foi possível continuar', error.message);
  }
  if (error is ArgumentError) {
    final m = error.message;
    return FriendlyError(
        ErrorKind.validation,
        'Confira os dados',
        m is String && m.isNotEmpty
            ? m
            : 'Algumas informações estão faltando.');
  }
  return _unknown;
}

/// Atalho: só a frase para a tela.
String friendlyMessage(Object error) => describeError(error).text;
