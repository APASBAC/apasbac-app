import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/models/monitoring_model.dart';
import '../../../../core/utils/image_url.dart';
import '../../../../core/widgets/network_photo.dart';

/// Fotos e vídeo do monitoramento: vídeo em destaque com capa e fotos em grade.
/// Tocar abre o visualizador em tela cheia.
class MonitoringMediaSection extends StatelessWidget {
  final List<MonitoringMedia> medias;
  const MonitoringMediaSection({super.key, required this.medias});

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) =>
          MediaViewerPage(medias: medias, initialIndex: index),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final videos = [
      for (var i = 0; i < medias.length; i++)
        if (medias[i].isVideo) i
    ];
    final photos = [
      for (var i = 0; i < medias.length; i++)
        if (!medias[i].isVideo) i
    ];
    final summary = [
      if (photos.isNotEmpty)
        '${photos.length} ${photos.length == 1 ? 'foto' : 'fotos'}',
      if (videos.isNotEmpty)
        '${videos.length} ${videos.length == 1 ? 'vídeo' : 'vídeos'}',
    ].join(' · ');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('$summary · toque para ver em tela cheia',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      const SizedBox(height: 10),
      for (final i in videos) ...[
        _VideoTile(media: medias[i], onTap: () => _open(context, i)),
        const SizedBox(height: 8),
      ],
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: photos.length,
        itemBuilder: (_, k) {
          final i = photos[k];
          return Material(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(context, i),
              child: Hero(
                tag: 'media-${medias[i].url}',
                child: NetworkPhoto(
                    url: medias[i].url, fit: BoxFit.cover, cacheWidth: 420),
              ),
            ),
          );
        },
      ),
    ]);
  }
}

class _VideoTile extends StatelessWidget {
  final MonitoringMedia media;
  final VoidCallback onTap;
  const _VideoTile({required this.media, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final poster = videoPosterUrl(media.url);
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            if (poster != null)
              NetworkPhoto(
                url: poster,
                fit: BoxFit.cover,
                cacheWidth: 900,
                error: const ColoredBox(color: Colors.black),
                placeholder: const ColoredBox(color: Colors.black),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xAA000000)]),
              ),
            ),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .92),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 16)
                  ],
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 40, color: Colors.black87),
              ),
            ),
            const Positioned(
              left: 14,
              bottom: 12,
              child: Row(children: [
                Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text('Vídeo do monitoramento',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Visualizador em tela cheia: desliza entre fotos e vídeo, zoom nas fotos,
/// controles que somem com um toque, miniaturas e arrastar para baixo fecha.
class MediaViewerPage extends StatefulWidget {
  final List<MonitoringMedia> medias;
  final int initialIndex;
  const MediaViewerPage(
      {super.key, required this.medias, this.initialIndex = 0});

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _ui = true;
  bool _zoomed = false;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _pages.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  void _setUi(bool visible) {
    if (_ui == visible) return;
    setState(() => _ui = visible);
    SystemChrome.setEnabledSystemUIMode(
        visible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _toggleUi() => _setUi(!_ui);

  @override
  Widget build(BuildContext context) {
    final media = widget.medias[_index];
    final total = widget.medias.length;
    final opacity = (1 - (_drag.abs() / 400)).clamp(0.3, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: GestureDetector(
        // Arrastar para baixo (sem zoom) fecha o visualizador.
        onVerticalDragUpdate:
            _zoomed ? null : (d) => setState(() => _drag += d.delta.dy),
        onVerticalDragEnd: _zoomed
            ? null
            : (d) {
                if (_drag.abs() > 140 || (d.primaryVelocity ?? 0).abs() > 900) {
                  Navigator.of(context).pop();
                } else {
                  setState(() => _drag = 0);
                }
              },
        child: Stack(children: [
          Transform.translate(
            offset: Offset(0, _drag),
            child: PageView.builder(
              controller: _pages,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: total,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (_, i) {
                final m = widget.medias[i];
                return m.isVideo
                    ? _VideoPage(
                        url: m.url,
                        active: i == _index,
                        controlsVisible: _ui,
                        onToggleUi: _toggleUi,
                        onShowUi: () => _setUi(true),
                        onHideUi: () => _setUi(false),
                      )
                    : _ZoomablePhoto(
                        url: m.url,
                        onTap: _toggleUi,
                        onZoomChanged: (z) {
                          if (z != _zoomed) setState(() => _zoomed = z);
                        },
                      );
              },
            ),
          ),
          // Barra superior: fechar, contador e tipo.
          AnimatedOpacity(
            opacity: _ui ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_ui,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    8, MediaQuery.of(context).padding.top + 4, 16, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Colors.transparent]),
                ),
                child: Row(children: [
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(media.isVideo ? 'Vídeo' : 'Foto',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text('${_index + 1} de $total',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 15)),
                ]),
              ),
            ),
          ),
          // Miniaturas para pular direto (fotos; o vídeo tem os próprios controles).
          if (total > 1 && !media.isVideo)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _ui ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_ui,
                  child: _Thumbnails(
                    medias: widget.medias,
                    index: _index,
                    onTap: (i) => _pages.animateToPage(i,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOut),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Thumbnails extends StatelessWidget {
  final List<MonitoringMedia> medias;
  final int index;
  final ValueChanged<int> onTap;
  const _Thumbnails(
      {required this.medias, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 18, 12, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC000000), Colors.transparent]),
      ),
      child: SizedBox(
        height: 56,
        child: Center(
          child: ListView.separated(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            itemCount: medias.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final m = medias[i];
              final selected = i == index;
              final thumb = m.isVideo ? videoPosterUrl(m.url) : m.url;
              return GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected ? Colors.white : Colors.white24,
                        width: selected ? 2.5 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    if (thumb != null)
                      NetworkPhoto(
                          url: thumb,
                          fit: BoxFit.cover,
                          cacheWidth: 168,
                          error: const ColoredBox(color: Colors.black54))
                    else
                      const ColoredBox(color: Colors.black54),
                    if (m.isVideo)
                      const Center(
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 26)),
                    if (!selected) const ColoredBox(color: Color(0x55000000)),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Foto com zoom por pinça e toque duplo (amplia no ponto tocado).
class _ZoomablePhoto extends StatefulWidget {
  final String url;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;
  const _ZoomablePhoto(
      {required this.url, required this.onTap, required this.onZoomChanged});

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _anim;
  Matrix4Tween? _tween;
  Offset _tapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() => _transform.value = _tween!.evaluate(_anim));
    _transform.addListener(() =>
        widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01));
  }

  @override
  void dispose() {
    _anim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _doubleTap() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    const scale = 2.6;
    final end = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(
              -_tapAt.dx * (scale - 1), -_tapAt.dy * (scale - 1), 0, 1)
          ..scaleByDouble(scale, scale, 1, 1));
    _tween = Matrix4Tween(begin: _transform.value, end: end);
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(
          child: Hero(
            tag: 'media-${widget.url}',
            child: NetworkPhoto(
              url: widget.url,
              fit: BoxFit.contain,
              placeholder: const Center(
                  child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))),
              error: const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.broken_image_outlined,
                    color: Colors.white70, size: 48),
                SizedBox(height: 8),
                Text(
                    'Não foi possível carregar a foto. Toque para tentar de novo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70)),
              ])),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vídeo com controles profissionais: play/pause central, barra de progresso
/// com arraste, tempo, som e tela cheia na horizontal. Controles somem sozinhos.
class _VideoPage extends StatefulWidget {
  final String url;
  final bool active;
  final bool controlsVisible;
  final VoidCallback onToggleUi;
  final VoidCallback onShowUi;
  final VoidCallback onHideUi;
  const _VideoPage({
    required this.url,
    required this.active,
    required this.controlsVisible,
    required this.onToggleUi,
    required this.onShowUi,
    required this.onHideUi,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _landscape = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.active && _c == null) _load();
    if (!widget.active) _c?.pause();
    if (widget.controlsVisible && !old.controlsVisible) _scheduleHide();
  }

  Future<void> _load() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    setState(() {
      _c = c;
      _failed = false;
    });
    c.addListener(_onTick);
    try {
      await c.initialize();
      if (!mounted) return;
      if (widget.active) await c.play();
      _scheduleHide();
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final v = _c!.value;
    if (v.hasError && !_failed) setState(() => _failed = true);
    if (v.isCompleted) {
      _hide?.cancel();
      widget.onShowUi();
    }
    setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) widget.onHideUi();
    });
  }

  Future<void> _togglePlay() async {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
      _hide?.cancel();
      widget.onShowUi();
    } else {
      if (c.value.isCompleted) await c.seekTo(Duration.zero);
      await c.play();
      _scheduleHide();
    }
  }

  Future<void> _toggleLandscape() async {
    _landscape = !_landscape;
    await SystemChrome.setPreferredOrientations(_landscape
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight
          ]
        : const []);
    if (_landscape) widget.onHideUi();
    setState(() {});
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  static String _time(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:${m.padLeft(2, '0')}:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_off_rounded,
              color: Colors.white70, size: 52),
          const SizedBox(height: 10),
          const Text('Não foi possível carregar o vídeo.',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 4),
          const Text('Verifique sua conexão.',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54)),
            onPressed: () {
              _c?.removeListener(_onTick);
              _c?.dispose();
              _c = null;
              _load();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar de novo'),
          ),
        ]),
      );
    }
    if (c == null || !c.value.isInitialized) {
      final poster = videoPosterUrl(widget.url, width: 1080);
      return Stack(fit: StackFit.expand, children: [
        if (poster != null)
          NetworkPhoto(
              url: poster, fit: BoxFit.contain, error: const SizedBox()),
        const Center(child: CircularProgressIndicator(color: Colors.white)),
      ]);
    }
    final v = c.value;
    final visible = widget.controlsVisible;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onToggleUi();
        if (!visible) _scheduleHide();
      },
      onDoubleTap: _togglePlay,
      child: Stack(fit: StackFit.expand, children: [
        Center(
            child:
                AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(c))),
        if (v.isBuffering)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        // Play/pause central: aparece com os controles, nunca fica fixo na imagem.
        IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible && !v.isBuffering ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  iconSize: 54,
                  padding: const EdgeInsets.all(14),
                  tooltip: v.isPlaying ? 'Pausar' : 'Reproduzir',
                  onPressed: _togglePlay,
                  icon: Icon(
                      v.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        // Barra inferior: progresso, tempo, som e tela cheia.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    16, 24, 8, MediaQuery.of(context).padding.bottom + 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Colors.transparent]),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    height: 22,
                    child: VideoProgressIndicator(
                      c,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white12),
                    ),
                  ),
                  Row(children: [
                    Text('${_time(v.position)} / ${_time(v.duration)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    const Spacer(),
                    IconButton(
                      tooltip: v.volume == 0 ? 'Ativar som' : 'Sem som',
                      onPressed: () => c.setVolume(v.volume == 0 ? 1 : 0),
                      icon: Icon(
                          v.volume == 0
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white),
                    ),
                    IconButton(
                      tooltip: _landscape ? 'Sair da tela cheia' : 'Tela cheia',
                      onPressed: _toggleLandscape,
                      icon: Icon(
                          _landscape
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
