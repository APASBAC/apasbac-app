import 'dart:collection';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Baixa fotos pelo Dio (mesmo cliente HTTP que já funciona para a API), com
/// limite de tempo e cache em memória. Substitui o cached_network_image, que
/// ficava preso em "carregando" no APK de release.
class PhotoCache {
  PhotoCache._();

  static final Dio _http = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45),
    responseType: ResponseType.bytes,
    followRedirects: true,
  ));

  static const _maxEntries = 80;
  static final _cache = LinkedHashMap<String, Future<Uint8List>>();

  static Future<Uint8List> load(String url) {
    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached; // marca como usado recentemente
      return cached;
    }
    final future = _download(url);
    _cache[url] = future;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    // Falhas não ficam em cache: a próxima tentativa baixa de novo.
    future.catchError((Object _) {
      if (identical(_cache[url], future)) _cache.remove(url);
      return Uint8List(0);
    });
    return future;
  }

  static Future<Uint8List> _download(String url) async {
    final response = await _http.get<List<int>>(url);
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw StateError('Imagem vazia');
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  static void evict(String url) => _cache.remove(url);
}

class NetworkPhoto extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width, height;

  /// Largura de decodificação em pixels (economiza memória em miniaturas).
  final int? cacheWidth;
  final Widget? placeholder;
  final Widget? error;

  const NetworkPhoto({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.placeholder,
    this.error,
  });

  @override
  State<NetworkPhoto> createState() => _NetworkPhotoState();
}

class _NetworkPhotoState extends State<NetworkPhoto> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = PhotoCache.load(widget.url);
  }

  @override
  void didUpdateWidget(NetworkPhoto old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _bytes = PhotoCache.load(widget.url);
  }

  void _retry() {
    PhotoCache.evict(widget.url);
    setState(() => _bytes = PhotoCache.load(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget box(Widget child) => SizedBox(
        width: widget.width, height: widget.height, child: child);

    if (widget.url.isEmpty) return box(widget.error ?? _ErrorBox(cs: cs));

    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) {
          return box(GestureDetector(
            onTap: _retry,
            child: widget.error ?? _ErrorBox(cs: cs, retry: true),
          ));
        }
        if (!snap.hasData) {
          return box(widget.placeholder ??
              ColoredBox(
                color: cs.surfaceContainerHighest,
                child: const Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              ));
        }
        return Image.memory(
          snap.data!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          cacheWidth: widget.cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              box(widget.error ?? _ErrorBox(cs: cs)),
        );
      },
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final ColorScheme cs;
  final bool retry;
  const _ErrorBox({required this.cs, this.retry = false});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.pets, color: cs.onSurfaceVariant),
            if (retry)
              Text('Tocar para tentar de novo',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        ),
      );
}
