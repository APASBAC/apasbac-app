import '../../../../core/widgets/apasbac_loading.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../providers.dart';
import '../../../../core/models/animal_model.dart';

class MyAnimalsScreen extends ConsumerWidget {
  const MyAnimalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animalsAsync = ref.watch(myAnimalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Animais'),
        leading: BackButton(onPressed: () => context.go('/home')),
      ),
      body: animalsAsync.when(
        loading: () => const ApasbacLoading(),
        error: (err, _) => _ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(myAnimalsProvider),
        ),
        data: (animals) {
          if (animals.isEmpty) {
            return _EmptyView();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myAnimalsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: animals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _AnimalCard(animal: animals[i]),
            ),
          );
        },
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final AnimalModel animal;
  const _AnimalCard({required this.animal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photo = animal.primaryPhoto;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/home/animals/${animal.id}'),
        child: Row(
          children: [
            // Foto
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(16)),
              child: SizedBox(
                width: 110,
                height: 110,
                child: photo != null
                    ? CachedNetworkImage(
                        imageUrl: photo.url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: cs.surfaceVariant,
                          child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (_, __, ___) => _PhotoPlaceholder(),
                      )
                    : _PhotoPlaceholder(),
              ),
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animal.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(animal.breed,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        _Chip(animal.sexLabel),
                        _Chip(animal.sizeLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.soft,
      child: const Icon(Icons.pets, size: 40, color: AppColors.muted),
    );
  }
}

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 80, color: AppColors.soft),
          const SizedBox(height: 16),
          const Text('Nenhum animal adotado ainda',
              style: TextStyle(fontSize: 16, color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: AppColors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: onRetry, child: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }
}
