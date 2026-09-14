import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../../../../providers.dart';
import '../../../../core/models/monitoring_model.dart';

class MonitoringDetailScreen extends ConsumerWidget {
  final String id;
  const MonitoringDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mAsync = ref.watch(monitoringDetailProvider(id));
    final user = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoramento'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(monitoringDetailProvider(id)),
          ),
        ],
      ),
      body: mAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Erro: $err')),
        data: (m) => _MonitoringDetailView(monitoring: m),
      ),
      floatingActionButton: mAsync.whenOrNull(
        data: (m) => user?.isTutor == true && m.canSubmit
            ? FloatingActionButton.extended(
                onPressed: () => context.push('/home/monitoring/$id/submit'),
                icon: const Icon(Icons.upload_rounded),
                label: const Text('Enviar relatório'),
              )
            : null,
      ),
    );
  }
}

class _MonitoringDetailView extends StatelessWidget {
  final MonitoringModel monitoring;
  const _MonitoringDetailView({required this.monitoring});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de status
          _StatusBanner(monitoring: monitoring),
          const SizedBox(height: 20),

          // Info do animal
          if (monitoring.animal != null) ...[
            _SectionTitle('Animal'),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundImage: monitoring.animal!.primaryPhoto != null
                      ? CachedNetworkImageProvider(monitoring.animal!.primaryPhoto!.url)
                      : null,
                  backgroundColor: cs.primaryContainer,
                  child: monitoring.animal!.primaryPhoto == null
                      ? Icon(Icons.pets, color: cs.onPrimaryContainer)
                      : null,
                ),
                title: Text(monitoring.animal!.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${monitoring.animal!.breed} · ${monitoring.animal!.sexLabel}'),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: () =>
                      context.push('/home/animals/${monitoring.animal!.id}'),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Datas
          _SectionTitle('Informações'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Criado em',
                    value: monitoring.createdAt != null
                        ? DateFormat('dd/MM/yyyy HH:mm').format(monitoring.createdAt!)
                        : '-',
                  ),
                  if (monitoring.dueDate != null) ...[
                    const Divider(height: 20),
                    _InfoRow(
                      icon: Icons.event_outlined,
                      label: 'Prazo',
                      value: DateFormat('dd/MM/yyyy').format(monitoring.dueDate!),
                    ),
                  ],
                  if (monitoring.notes != null) ...[
                    const Divider(height: 20),
                    _InfoRow(
                      icon: Icons.notes_outlined,
                      label: 'Observações',
                      value: monitoring.notes!,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Nota de revisão (se rejeitado ou aprovado)
          if (monitoring.reviewNotes != null) ...[
            _SectionTitle('Nota da revisão'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: monitoring.isRejected
                    ? Colors.red.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: monitoring.isRejected
                      ? Colors.red.shade200
                      : Colors.green.shade200,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    monitoring.isRejected
                        ? Icons.info_outline
                        : Icons.check_circle_outline,
                    color: monitoring.isRejected ? Colors.red : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      monitoring.reviewNotes!,
                      style: TextStyle(
                        color: monitoring.isRejected
                            ? Colors.red.shade800
                            : Colors.green.shade800,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Mídias enviadas
          if (monitoring.medias.isNotEmpty) ...[
            _SectionTitle('Mídias enviadas (${monitoring.medias.length})'),
            const SizedBox(height: 10),
            _MediaGrid(medias: monitoring.medias),
            const SizedBox(height: 20),
          ],

          // Estado "em análise"
          if (monitoring.isUnderReview) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Seu envio está sendo revisado pela equipe da APASBAC. Aguarde o resultado.',
                      style: TextStyle(color: Colors.blue.shade800, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 80), // espaço para FAB
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final MonitoringModel monitoring;
  const _StatusBanner({required this.monitoring});

  Color get _color => switch (monitoring.status) {
        'PENDING' => Colors.orange,
        'IN_REVIEW' => Colors.blue,
        'APPROVED' => Colors.green,
        'REJECTED' => Colors.red,
        _ => Colors.grey,
      };

  IconData get _icon => switch (monitoring.status) {
        'PENDING' => Icons.hourglass_empty_rounded,
        'IN_REVIEW' => Icons.manage_search_rounded,
        'APPROVED' => Icons.check_circle_rounded,
        'REJECTED' => Icons.cancel_rounded,
        _ => Icons.help_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(_icon, color: _color, size: 40),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status do monitoramento',
                  style: TextStyle(fontSize: 12, color: _color.withOpacity(0.8))),
              const SizedBox(height: 2),
              Text(
                monitoring.statusLabel,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: _color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  final List<MonitoringMedia> medias;
  const _MediaGrid({required this.medias});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: medias.length,
      itemBuilder: (_, i) {
        final media = medias[i];
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => _MediaPreviewDialog(media: media),
                ),
                child: media.isVideo
                    ? Container(
                        color: Colors.black87,
                        child: const Icon(Icons.play_circle_filled_rounded,
                            color: Colors.white, size: 40),
                      )
                    : CachedNetworkImage(
                        imageUrl: media.url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.grey.shade200),
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image_outlined)),
                      ),
              ),
              if (media.isVideo)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('VID',
                        style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaPreviewDialog extends StatelessWidget {
  final MonitoringMedia media;
  const _MediaPreviewDialog({required this.media});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            Positioned.fill(
              child: media.isVideo
                  ? _NetworkVideoPlayer(url: media.url)
                  : InteractiveViewer(
                      child: CachedNetworkImage(
                        imageUrl: media.url,
                        fit: BoxFit.contain,
                        placeholder: (_, __) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkVideoPlayer extends StatefulWidget {
  final String url;
  const _NetworkVideoPlayer({required this.url});

  @override
  State<_NetworkVideoPlayer> createState() => _NetworkVideoPlayerState();
}

class _NetworkVideoPlayerState extends State<_NetworkVideoPlayer> {
  late final VideoPlayerController _controller;
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _init = _controller.initialize().then((_) {
      _controller.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!_controller.value.isInitialized) {
          return const Center(child: Icon(Icons.error_outline));
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
            IconButton.filled(
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              icon: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(label,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
