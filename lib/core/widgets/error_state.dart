import 'package:flutter/material.dart';

import '../utils/friendly_error.dart';

/// Tela/área de erro com ícone pelo tipo do problema e botão de tentar de novo.
class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ErrorState({super.key, required this.error, this.onRetry});

  static IconData iconFor(ErrorKind kind) => switch (kind) {
        ErrorKind.offline => Icons.wifi_off_rounded,
        ErrorKind.timeout => Icons.hourglass_empty_rounded,
        ErrorKind.server => Icons.cloud_off_rounded,
        ErrorKind.session => Icons.lock_clock_outlined,
        ErrorKind.permission => Icons.block_rounded,
        ErrorKind.notFound => Icons.search_off_rounded,
        ErrorKind.update => Icons.system_update_rounded,
        _ => Icons.error_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final e = describeError(error);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: cs.surfaceContainerHighest, shape: BoxShape.circle),
            child: Icon(iconFor(e.kind), size: 40, color: cs.primary),
          ),
          const SizedBox(height: 18),
          Text(e.title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(e.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.45)),
          if (onRetry != null) ...[
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar de novo'),
            ),
          ],
        ]),
      ),
    );
  }
}
