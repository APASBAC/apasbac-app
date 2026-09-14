import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../../../providers.dart';

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
  XFile? _video;
  final List<XFile> _images = [];
  bool _loading = false;
  String? _error;
  double _uploadProgress = 0;

  static const int _maxImages = 5;

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked != null && mounted) {
      setState(() => _video = picked);
    }
  }

  Future<void> _pickImages() async {
    if (_images.length >= _maxImages) {
      _showSnack('Máximo de $_maxImages imagens atingido');
      return;
    }
    final remaining = _maxImages - _images.length;
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty && mounted) {
      final toAdd = picked.take(remaining).toList();
      setState(() => _images.addAll(toAdd));
    }
  }

  Future<void> _takePhoto() async {
    if (_images.length >= _maxImages) {
      _showSnack('Máximo de $_maxImages imagens atingido');
      return;
    }
    final picked =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null && mounted) {
      setState(() => _images.add(picked));
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
      _uploadProgress = 0;
    });

    try {
      await ref.read(monitoringServiceProvider).submitMonitoring(
            monitoringId: widget.monitoringId,
            video: _video!,
            images: _images,
            onProgress: (value) {
              if (mounted) setState(() => _uploadProgress = value);
            },
          );

      if (mounted) {
        // Invalida o cache para recarregar o detalhe
        ref.invalidate(monitoringDetailProvider(widget.monitoringId));
        ref.invalidate(myMonitoringsProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Relatório enviado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      String msg;
      if (data is Map) {
        final raw = data['message'] ?? 'Erro ao enviar';
        msg = raw is List ? raw.join(', ') : raw.toString();
      } else if (data is String && data.isNotEmpty) {
        final status = e.response?.statusCode;
        msg = status == 503
            ? 'Serviço temporariamente indisponível. Tente novamente em instantes.'
            : 'Erro ${status ?? ""}: verifique sua conexão e tente novamente.';
      } else {
        msg = 'Erro ao enviar. Tente novamente.';
      }
      if (mounted) setState(() => _error = msg);
    } catch (e) {
      if (mounted) setState(() => _error = 'Erro inesperado: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                      'Envie um vídeo e exatamente 5 fotos mostrando como o animal está.',
                      style:
                          TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
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
                    onPressed: _loading ? null : _pickVideo,
                    icon: const Icon(Icons.video_library_outlined, size: 18),
                    label: const Text('Selecionar'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_video == null)
              _PickerPlaceholder(
                icon: Icons.videocam_outlined,
                label: 'Toque para adicionar um vídeo',
                onTap: _loading ? null : _pickVideo,
              )
            else
              _VideoPreviewTile(
                file: _video!,
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
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_images.isEmpty)
              _PickerPlaceholder(
                icon: Icons.photo_outlined,
                label: 'Toque para adicionar 5 fotos obrigatórias',
                onTap: _loading ? null : _pickImages,
              )
            else
              _ImageGrid(
                images: _images,
                maxImages: _maxImages,
                onRemove: _loading ? null : _removeImage,
                onAdd: _images.length < _maxImages && !_loading
                    ? _pickImages
                    : null,
                onAddCamera: _images.length < _maxImages && !_loading
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
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _loading
                      ? 'Enviando ${(_uploadProgress * 100).round()}%'
                      : 'Enviar relatório',
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
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
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
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
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
                color: Colors.white, size: 28),
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
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            color: Colors.red,
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
  final VoidCallback? onAdd;
  final VoidCallback? onAddCamera;

  const _ImageGrid({
    required this.images,
    required this.maxImages,
    this.onRemove,
    this.onAdd,
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
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              // Slot vazio
              final isNextEmpty = i == images.length;
              return GestureDetector(
                onTap: isNextEmpty ? onAdd : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: isNextEmpty
                        ? cs.primaryContainer.withOpacity(0.25)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isNextEmpty
                          ? cs.primary.withOpacity(0.4)
                          : Colors.grey.shade300,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isNextEmpty
                            ? Icons.add_photo_alternate_outlined
                            : Icons.photo_outlined,
                        size: 26,
                        color: isNextEmpty
                            ? cs.primary.withOpacity(0.7)
                            : Colors.grey.shade300,
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
              Icon(Icons.info_outline, size: 13, color: Colors.red.shade400),
              const SizedBox(width: 5),
              Text(
                'Faltam $remaining foto${remaining > 1 ? 's' : ''} para completar',
                style: TextStyle(fontSize: 12, color: Colors.red.shade400),
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
              if (onAdd != null)
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 14, color: cs.onPrimary),
                        const SizedBox(width: 4),
                        Text('Galeria',
                            style:
                                TextStyle(fontSize: 12, color: cs.onPrimary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
