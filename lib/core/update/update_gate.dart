import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/apasbac_logo.dart';
import 'update_manager.dart';
import 'update_platform.dart';
import 'update_repository.dart';
import 'update_telemetry.dart';

final updateManagerProvider = ChangeNotifierProvider<UpdateManager>((ref) {
  final telemetry = UpdateTelemetry();
  return UpdateManager(
      repository: UpdateRepository(),
      platform: AndroidUpdatePlatform(),
      onEvent: (event, installed, target) =>
          unawaited(telemetry.send(event, installed, target)),
      drainTelemetry: () => unawaited(telemetry.drain()));
});

class UpdateGate extends ConsumerStatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});
  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(updateManagerProvider).start());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final manager = ref.read(updateManagerProvider);
    if (state == AppLifecycleState.resumed) {
      unawaited(manager.resume());
    } else {
      manager.background();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(updateManagerProvider);
    return Stack(children: [
      ExcludeSemantics(
          excluding: manager.visible,
          child: ExcludeFocus(
              excluding: manager.visible,
              child: AbsorbPointer(
                  absorbing: manager.visible, child: widget.child))),
      if (manager.visible)
        Positioned.fill(
            child: BlockSemantics(
          child: PopScope(
              canPop: false,
              child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                      child: Center(
                          child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: UpdatePanel(manager: manager)),
                  ))))),
        )),
    ]);
  }
}

class UpdatePanel extends StatelessWidget {
  final UpdateManager manager;
  const UpdatePanel({super.key, required this.manager});
  String _size(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) {
    final m = manager;
    final release = m.manifest;
    final progress = release == null
        ? 0.0
        : (m.downloaded / release.sizeBytes).clamp(0.0, 1.0);
    final label = switch (m.state) {
      UpdateState.checking => 'Verificando atualização...',
      UpdateState.downloading =>
        'Baixando atualização — ${(progress * 100).floor()}%',
      UpdateState.verifying => 'Verificando atualização...',
      UpdateState.readyToInstall => 'Preparando atualização...',
      UpdateState.installing => 'Instalando atualização...',
      UpdateState.needsUserPermission => 'Autorize a instalação para continuar',
      UpdateState.failed => 'Não foi possível atualizar',
      _ =>
        m.mandatory ? 'Atualização necessária' : 'Nova atualização disponível',
    };
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: ApasbacLogo()),
          const SizedBox(height: 24),
          Text(label, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text('Versão instalada: ${m.installed?.name ?? '—'}'),
          if (release != null) ...[
            Text(
                'Nova versão: ${release.versionName} • ${_size(release.sizeBytes)}'),
            const SizedBox(height: 16),
            for (final note in release.releaseNotes)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $note')),
          ],
          if (m.mandatory)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    'Atualize para continuar usando o aplicativo. Seus dados serão preservados.')),
          if (m.state == UpdateState.downloading) ...[
            LinearProgressIndicator(
                value: progress, semanticsLabel: 'Progresso do download'),
            const SizedBox(height: 8),
            Text('${_size(m.downloaded)} / ${_size(release!.sizeBytes)}'),
          ] else if (m.busy || m.state == UpdateState.checking)
            const LinearProgressIndicator(),
          if (m.message != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(m.message!)),
          if (m.failures >= 3)
            const Text(
                'A atualização falhou várias vezes. Verifique sua conexão ou entre em contato com a APASBAC antes de tentar novamente.'),
          const SizedBox(height: 20),
          if (m.state == UpdateState.needsUserPermission) ...[
            const Text(
                'Permita que a APASBAC instale a atualização na próxima tela. Depois, volte ao aplicativo.'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: m.grantPermission,
                child: const Text('Autorizar instalação')),
          ] else if (m.state == UpdateState.failed)
            FilledButton(
                onPressed: m.busy ? null : m.retry,
                child: const Text('Tentar novamente'))
          else if (m.state == UpdateState.updateAvailable)
            FilledButton(
                onPressed: m.busy ? null : m.download,
                child: const Text('Atualizar agora')),
          if (m.canPostpone)
            TextButton(onPressed: m.later, child: const Text('Depois')),
          if (!m.mandatory && m.state == UpdateState.downloading)
            TextButton(
                onPressed: m.cancel, child: const Text('Cancelar download')),
        ]);
  }
}
