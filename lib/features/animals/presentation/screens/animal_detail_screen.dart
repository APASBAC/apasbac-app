import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../providers.dart';
import '../../../../core/models/animal_model.dart';

class AnimalDetailScreen extends ConsumerWidget {
  final int id;
  const AnimalDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animalAsync = ref.watch(animalDetailProvider(id));

    return Scaffold(
      body: animalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Scaffold(
          appBar: AppBar(),
          body: Center(child: Text('Erro: $err')),
        ),
        data: (animal) => _AnimalDetailView(animal: animal),
      ),
    );
  }
}

class _AnimalDetailView extends StatefulWidget {
  final AnimalModel animal;
  const _AnimalDetailView({required this.animal});

  @override
  State<_AnimalDetailView> createState() => _AnimalDetailViewState();
}

class _AnimalDetailViewState extends State<_AnimalDetailView> {
  int _currentPhoto = 0;

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero com fotos
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: animal.photos.isNotEmpty
                  ? Stack(
                      children: [
                        PageView.builder(
                          itemCount: animal.photos.length,
                          onPageChanged: (i) => setState(() => _currentPhoto = i),
                          itemBuilder: (_, i) => CachedNetworkImage(
                            imageUrl: animal.photos[i].url,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: cs.surfaceVariant),
                            errorWidget: (_, __, ___) => Container(
                              color: cs.surfaceVariant,
                              child: const Icon(Icons.pets, size: 80, color: Colors.grey),
                            ),
                          ),
                        ),
                        if (animal.photos.length > 1)
                          Positioned(
                            bottom: 12,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                animal.photos.length,
                                (i) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _currentPhoto ? 18 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: i == _currentPhoto
                                        ? Colors.white
                                        : Colors.white54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Container(
                      color: cs.surfaceVariant,
                      child: const Icon(Icons.pets, size: 80, color: Colors.grey),
                    ),
            ),
          ),

          // Conteúdo
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome e chips
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          animal.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      _StatusChip(
                        label: animal.isAdopted ? 'Adotado' : 'Disponível',
                        color: animal.isAdopted ? Colors.green : Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    animal.breed,
                    style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),

                  // Info chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(icon: Icons.male, label: animal.sexLabel, color: cs.primary),
                      _InfoChip(icon: Icons.straighten, label: animal.sizeLabel, color: cs.secondary),
                      if (animal.escapeTendency)
                        _InfoChip(
                          icon: Icons.warning_amber_rounded,
                          label: 'Foge com facilidade',
                          color: Colors.orange,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _Section(
                    title: 'Descrição',
                    child: Text(animal.description,
                        style: const TextStyle(fontSize: 15, height: 1.5)),
                  ),
                  const SizedBox(height: 20),

                  _Section(
                    title: 'Temperamento',
                    child: Text(animal.temperament,
                        style: const TextStyle(fontSize: 15, height: 1.5)),
                  ),
                  const SizedBox(height: 20),

                  _Section(
                    title: 'Vacinas',
                    child: animal.vaccines.isEmpty
                        ? Text('Nenhuma vacina registrada',
                            style: TextStyle(color: cs.onSurfaceVariant))
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: animal.vaccines
                                .map((v) => Chip(
                                      label: Text(v),
                                      avatar: const Icon(Icons.vaccines, size: 16),
                                      visualDensity: VisualDensity.compact,
                                    ))
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
    );
  }
}
