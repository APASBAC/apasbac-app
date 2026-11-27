import '../../../../core/utils/friendly_error.dart';
import '../../../../core/theme/semantic_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../../../providers.dart';
import '../widgets/upload_status_card.dart';
import '../../../../core/services/capture_attestation.dart';

class MonitoringSubmitScreen extends ConsumerStatefulWidget {
  final String monitoringId;
  const MonitoringSubmitScreen({super.key, required this.monitoringId});

  @override
  ConsumerState<MonitoringSubmitScreen> createState() =>
      _MonitoringSubmitScreenState();
}

class _MonitoringSubmitScreenState
    extends ConsumerState<MonitoringSubmitScreen> {
  final _picker = ImagePicker();
  CapturedFile? _video;
  final List<CapturedFile> _images = [];
  bool _loading = false;
  bool _capturing = false;
  String? _error;

  /// Sessão de captura: sem ela não dá para gravar (a API recusaria o envio).
  CaptureSession? _session;
  Object? _sessionError;

  static const int _maxImages = 5;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    setState(() {
      _session = null;
      _sessionError = null;
    });
    try {
      final s = await ref
          .read(monitoringServiceProvider)
          .captureSession(widget.monitoringId);
      if (mounted) setState(() => _session = s);
    } catch (e) {
      if (mounted) setState(() => _sessionError = e);
    }
  }

  /// Grava pela câmera e assina na hora. Galeria e outros apps não são aceitos.
  Future<CapturedFile?> _capture(
      Future<XFile?> Function() open, String kind) async {
    final session = _session;
    if (session == null || _capturing) return null;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final file = await open();
      if (file == null) return null;
      return await attestCapture(file, kind: kind, session: session);
    } catch (e) {
      if (mounted)
        setState(() =>
            _error = 'Não foi possível usar a câmera. ${friendlyMessage(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _recordVideo() async {
    final c = await _capture(
        () => _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 3)),
        'video');
    if (c != null && mounted) setState(() => _video = c);
  }

  /// Abre a câmera em sequência até completar as 5 fotos: tirou uma, a próxima
  /// já abre. Cancelar na câmera interrompe (dá para continuar depois).
  Future<void> _takePhoto() async {
    if (_images.length >= _maxImages) {
      _showSnack('As $_maxImages fotos já foram tiradas');
      return;
    }
    while (mounted && _images.length < _maxImages) {
      final c = await _capture(
          () => _picker.pickImage(source: ImageSource.camera, imageQuality: 80),
          'image');
      if (c == null || !mounted) break;
      setState(() => _images.add(c));
      final left = _maxImages - _images.length;
      if (left > 0) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 1200),
          content: Text(
              'Foto ${_images.length} de $_maxImages salva. Abrindo a câmera para a próxima…'),
        ));
      }
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  void _removeVideo() {
    setState(() => _video = null);
  }

  Future<void> _submit() async {
    if (_video == null) {
      setState(() => _error = 'O envio do vídeo é obrigatório.');
      return;
    }
    if (_images.length < _maxImages) {
      setState(() => _error = 'Adicione exatamente $_maxImages fotos.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Confere se o monitoramento ainda aceita envio. Sem internet, o envio
      // entra na fila mesmo assim e começa quando a conexão voltar.
      try {
        final current = await ref
            .read(monitoringServiceProvider)
            .getMonitoringById(widget.monitoringId, withAnimal: false);
        if (!current.canSubmit) {
          if (mounted) {
            setState(
                () => _error = 'Este monitoramento não aceita mais envios.');
          }
          return;
        }
      } on DioException catch (e) {
        if (e.response != null && e.response!.statusCode! < 500) rethrow;
      }

      final animal = ref
          .read(monitoringDetailProvider(widget.monitoringId))
          .valueOrNull
          ?.animal
          ?.name;
      final session = _session;
      if (session == null || session.expired) {
        setState(() => _error =
            'A sessão de gravação expirou. Grave as fotos e o vídeo novamente.');
        _video = null;
        _images.clear();
        await _loadSession();
        return;
      }
      await ref.read(uploadQueueProvider).enqueue(
            monitoringId: widget.monitoringId,
            animalName: animal ?? '',
            video: _video!,
            images: List.of(_images),
            captureToken: session.token,
            captureKey: session.key,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Enviando em segundo plano. Pode sair do app: avisamos quando terminar.'),
            backgroundColor: SemanticColors.approved,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError
            ? e.message
            : 'Não foi possível preparar o envio. ${friendlyMessage(e)}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canCapture => _session != null && !_loading && !_capturing;

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final job = ref.watch(uploadQueueProvider).jobFor(widget.monitoringId);
    if (job != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Enviar relatório')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          UploadStatusCard(monitoringId: widget.monitoringId),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Enviar relatório')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header informativo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Grave um vídeo e tire 5 fotos agora, pela câmera do aplicativo, mostrando como o animal está. '
                      'Fotos e vídeos da galeria ou de outros apps não são aceitos.',
                      style:
                          TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            if (_session == null) ...[
              const SizedBox(height: 16),
              _sessionError == null
                  ? const Row(children: [
                      SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Preparando a câmera segura…'),
                    ])
                  : Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Não foi possível liberar a câmera. ${friendlyMessage(_sessionError!)}',
                                style: TextStyle(color: cs.onErrorContainer)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _loadSession,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Tentar de novo'),
                            ),
                          ]),
                    ),
            ],
            const SizedBox(height: 28),

            // ── Seção vídeo ────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Vídeo (obrigatório)',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (_video == null)
                  TextButton.icon(
                    onPressed: _canCapture ? _recordVideo : null,
                    icon: const Icon(Icons.videocam_rounded, size: 18),
                    label: const Text('Gravar'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_video == null)
              _PickerPlaceholder(
                icon: Icons.videocam_outlined,
                label: 'Toque para gravar o vídeo',
                onTap: _canCapture ? _recordVideo : null,
              )
            else
              _VideoPreviewTile(
                file: _video!.file,
                onRemove: _loading ? null : _removeVideo,
              ),

            const SizedBox(height: 28),

            // ── Seção fotos ────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fotos (${_images.length}/$_maxImages — obrigatório)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _images.length < _maxImages
                        ? AppColors.muted
                        : AppColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_images.isEmpty)
              _PickerPlaceholder(
                icon: Icons.camera_alt_outlined,
                label: 'Toque para tirar as 5 fotos em sequência',
                onTap: _canCapture ? _takePhoto : null,
              )
            else
              _ImageGrid(
                images: [for (final c in _images) c.file],
                maxImages: _maxImages,
                onRemove: _loading ? null : _removeImage,
                onAddCamera: _images.length < _maxImages && _canCapture
                    ? _takePhoto
                    : null,
              ),

            // ── Erro ───────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: cs.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: cs.onErrorContainer, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // ── Botão enviar ──────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.cream),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _loading ? 'Preparando envio…' : 'Enviar relatório',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ─────────────────────────────────────────

class _PickerPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PickerPlaceholder({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.soft,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: AppColors.muted),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _VideoPreviewTile extends StatelessWidget {
  final XFile file;
  final VoidCallback? onRemove;

  const _VideoPreviewTile({required this.file, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final name = file.path.split('/').last;
    const sizeLabel = 'Vídeo selecionado';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.soft),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.play_circle_fill_rounded,
                color: AppColors.cream, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13)),
                Text(sizeLabel,
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            color: AppColors.red,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<XFile> images;
  final int maxImages;
  final void Function(int)? onRemove;
  final VoidCallback? onAddCamera;

  const _ImageGrid({
    required this.images,
    required this.maxImages,
    this.onRemove,
    this.onAddCamera,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = maxImages - images.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: maxImages,
          itemBuilder: (_, i) {
            if (i < images.length) {
              // Slot preenchido
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: FutureBuilder(
                        future: images[i].readAsBytes(),
                        builder: (context, snapshot) => snapshot.hasData
                            ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                            : const Center(child: CircularProgressIndicator())),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: onRemove != null ? () => onRemove!(i) : null,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: AppColors.cream, size: 16),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              // Slot vazio
              final isNextEmpty = i == images.length;
              return GestureDetector(
                onTap: isNextEmpty ? onAddCamera : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: isNextEmpty
                        ? cs.primaryContainer.withOpacity(0.25)
                        : AppColors.soft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isNextEmpty
                          ? cs.primary.withOpacity(0.4)
                          : AppColors.soft,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isNextEmpty
                            ? Icons.add_a_photo_outlined
                            : Icons.photo_outlined,
                        size: 26,
                        color: isNextEmpty
                            ? cs.primary.withOpacity(0.7)
                            : AppColors.soft,
                      ),
                      if (isNextEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.primary.withOpacity(0.7),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }
          },
        ),
        if (remaining > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: AppColors.muted),
              const SizedBox(width: 5),
              Text(
                'Faltam $remaining foto${remaining > 1 ? 's' : ''} para completar',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const Spacer(),
              if (onAddCamera != null)
                GestureDetector(
                  onTap: onAddCamera,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 14, color: cs.primary),
                        const SizedBox(width: 4),
                        Text('Câmera',
                            style: TextStyle(fontSize: 12, color: cs.primary)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ],
    );
  }
}
