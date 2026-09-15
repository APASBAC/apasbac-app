import '../../../../core/widgets/apasbac_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../providers.dart';
import '../../../../core/models/create_animal.dart';
import '../../../../core/services/config_service.dart';
import '../../../../core/services/storage_service.dart';

final configsProvider = FutureProvider((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null || !user.isAdminOrStaff) return <Map<String, dynamic>>[];
  return ConfigService().getConfigs();
});

String configTitle(Map<String, dynamic> config) => switch (config['key']) {
      'monitoring_period_value' => 'Intervalo entre monitoramentos',
      'monitoring_period_unit' => 'Unidade do intervalo',
      'apasbac_email' => 'E-mail de contato',
      'apasbac_phone' => 'Telefone de contato',
      _ => (config['description'] as String?)?.trim().isNotEmpty == true
          ? config['description'] as String
          : (config['key'] as String).replaceAll('_', ' '),
    };

String configValue(Map<String, dynamic> config) {
  final value = config['value']?.toString() ?? '';
  if (value.isEmpty) return 'Não informado';
  if (config['key'] == 'monitoring_period_unit') {
    return const {
          'DAYS': 'Dias',
          'WEEKS': 'Semanas',
          'MONTHS': 'Meses',
          'YEARS': 'Anos'
        }[value] ??
        value;
  }
  return value;
}

class ConfigsTab extends ConsumerWidget {
  const ConfigsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(configsProvider)
      .when(
        loading: () => const ApasbacLoading(),
        error: (e, _) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Não foi possível carregar as configurações.'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: () => ref.invalidate(configsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente')),
        ])),
        data: (configs) {
          final groups = <String, List<Map<String, dynamic>>>{
            'Acompanhamento dos animais': [],
            'Contato da APASBAC': [],
            'Outras configurações': [],
          };
          for (final config in configs) {
            final key = config['key'] as String;
            groups[key.startsWith('monitoring_')
                    ? 'Acompanhamento dos animais'
                    : ['apasbac_email', 'apasbac_phone'].contains(key)
                        ? 'Contato da APASBAC'
                        : 'Outras configurações']!
                .add(config);
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(configsProvider);
              await ref.read(configsProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              children: [
                Text('Configurações',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                    'Ajuste o acompanhamento e os canais de contato. Toque em uma opção para editar.'),
                const SizedBox(height: 28),
                if (configs.isEmpty)
                  const Text('Nenhuma configuração disponível.'),
                for (final group
                    in groups.entries.where((g) => g.value.isNotEmpty)) ...[
                  Text(group.key,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(group.key == 'Acompanhamento dos animais'
                      ? 'Defina a frequência dos relatórios de acompanhamento.'
                      : group.key == 'Contato da APASBAC'
                          ? 'Mantenha os contatos da associação atualizados.'
                          : 'Ajustes adicionais do aplicativo.'),
                  const SizedBox(height: 14),
                  Card(
                      child: Column(children: [
                    for (var i = 0; i < group.value.length; i++) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        title: Text(configTitle(group.value[i])),
                        subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(configValue(group.value[i]))),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          final saved = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) =>
                                  _ConfigDialog(config: group.value[i]));
                          if (saved == true) {
                            ref.invalidate(configsProvider);
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Configuração atualizada.')));
                          }
                        },
                      ),
                    ],
                  ])),
                  const SizedBox(height: 28),
                ],
              ],
            ),
          );
        },
      );
}

class _ConfigDialog extends StatefulWidget {
  final Map<String, dynamic> config;
  const _ConfigDialog({required this.config});
  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<_ConfigDialog> {
  final form = GlobalKey<FormState>();
  late final value =
      TextEditingController(text: widget.config['value'] as String);
  late final description = TextEditingController(
      text: widget.config['description'] as String? ?? '');
  bool saving = false;
  String? error;
  @override
  void dispose() {
    value.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.config['key'] as String;
    return PopScope(
        canPop: !saving,
        child: AlertDialog(
          title: Text(configTitle(widget.config)),
          content: Form(
              key: form,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (key == 'monitoring_period_unit')
                  DropdownButtonFormField<String>(
                    initialValue: value.text,
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    items: const [
                      DropdownMenuItem(value: 'DAYS', child: Text('Dias')),
                      DropdownMenuItem(value: 'WEEKS', child: Text('Semanas')),
                      DropdownMenuItem(value: 'MONTHS', child: Text('Meses')),
                      DropdownMenuItem(value: 'YEARS', child: Text('Anos'))
                    ],
                    onChanged: saving ? null : (v) => value.text = v!,
                  )
                else
                  TextFormField(
                      controller: value,
                      enabled: !saving,
                      decoration: InputDecoration(
                          labelText: configTitle(widget.config)),
                      keyboardType: key == 'monitoring_period_value'
                          ? TextInputType.number
                          : key == 'apasbac_email'
                              ? TextInputType.emailAddress
                              : key == 'apasbac_phone'
                                  ? TextInputType.phone
                                  : TextInputType.text,
                      validator: (v) => ConfigService.validate(key, v!.trim())),
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Descrição da configuração'),
                  subtitle: const Text('Opcional'),
                  children: [
                    TextFormField(
                      controller: description,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: 'Descrição'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12)
                  ],
                ),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        setState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await ConfigService()
                              .update(key, value.text, description.text);
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (e) {
                          if (mounted) {
                            setState(
                                () => error = 'Não foi possível salvar: $e');
                          }
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
                child: Text(saving ? 'Salvando...' : 'Salvar alteração'))
          ],
        ));
  }
}

class AnimalCreateScreen extends ConsumerStatefulWidget {
  const AnimalCreateScreen({super.key});
  @override
  ConsumerState<AnimalCreateScreen> createState() => _AnimalCreateState();
}

class _AnimalCreateState extends ConsumerState<AnimalCreateScreen> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in ['Nome', 'Descrição', 'Raça', 'Temperamento', 'Vacinas'])
      key: TextEditingController()
  };
  String sex = 'MALE', size = 'MEDIUM';
  bool escape = false, saving = false;
  final photos = <XFile>[];
  final uploaded = <String, String>{};
  String? error;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Novo animal')),
        body: Form(
            key: form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              for (final entry in fields.entries)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: entry.value,
                      enabled: !saving,
                      decoration: InputDecoration(
                          labelText: entry.key,
                          helperText: entry.key == 'Vacinas'
                              ? 'Separe por vírgulas'
                              : null),
                      validator: (v) =>
                          ['Nome', 'Descrição', 'Raça'].contains(entry.key) &&
                                  v!.trim().isEmpty
                              ? 'Campo obrigatório'
                              : null,
                    )),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                  initialValue: sex,
                  decoration: const InputDecoration(labelText: 'Sexo'),
                  items: const [
                    DropdownMenuItem(value: 'MALE', child: Text('Macho')),
                    DropdownMenuItem(value: 'FEMALE', child: Text('Fêmea'))
                  ],
                  onChanged: saving ? null : (v) => setState(() => sex = v!)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                  initialValue: size,
                  decoration: const InputDecoration(labelText: 'Porte'),
                  items: const [
                    DropdownMenuItem(value: 'SMALL', child: Text('Pequeno')),
                    DropdownMenuItem(value: 'MEDIUM', child: Text('Médio')),
                    DropdownMenuItem(value: 'LARGE', child: Text('Grande')),
                    DropdownMenuItem(
                        value: 'EXTRA_LARGE', child: Text('Extra grande'))
                  ],
                  onChanged: saving ? null : (v) => setState(() => size = v!)),
              SwitchListTile(
                  title: const Text('Tendência a fugir'),
                  value: escape,
                  onChanged: saving ? null : (v) => setState(() => escape = v)),
              for (final photo in photos)
                ListTile(
                    title: Text(photo.name),
                    leading: const Icon(Icons.image),
                    trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: saving
                            ? null
                            : () => setState(() => photos.remove(photo)))),
              OutlinedButton.icon(
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text('Adicionar fotos (${photos.length}/3)'),
                  onPressed: saving || photos.length == 3
                      ? null
                      : () async {
                          try {
                            final selected = await ImagePicker()
                                .pickMultiImage(imageQuality: 85);
                            if (mounted) {
                              setState(() => photos
                                  .addAll(selected.take(3 - photos.length)));
                            }
                          } catch (e) {
                            if (mounted) {
                              setState(() => error =
                                  'Não foi possível selecionar fotos: $e');
                            }
                          }
                        }),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Salvando...' : 'Cadastrar animal')),
            ])),
      ));

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final storage = StorageService();
      for (final photo in photos) {
        uploaded[photo.path] ??=
            await storage.upload(photo, folder: 'animals/photos');
      }
      await ref.read(animalServiceProvider).createAnimal(CreateAnimal(
            name: fields['Nome']!.text,
            description: fields['Descrição']!.text,
            breed: fields['Raça']!.text,
            temperament: fields['Temperamento']!.text,
            sex: sex,
            size: size,
            escapeTendency: escape,
            vaccines: fields['Vacinas']!
                .text
                .split(',')
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toList(),
            photoUrls: photos.map((p) => uploaded[p.path]!).toList(),
          ));
      ref.invalidate(adminAnimalsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Animal cadastrado.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Não foi possível cadastrar: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class MonitoringCreateScreen extends ConsumerStatefulWidget {
  const MonitoringCreateScreen({super.key});
  @override
  ConsumerState<MonitoringCreateScreen> createState() =>
      _MonitoringCreateState();
}

class _MonitoringCreateState extends ConsumerState<MonitoringCreateScreen> {
  int? animalId;
  final notes = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Novo monitoramento')),
        body: ref.watch(adminAnimalsProvider).when(
              loading: () => const ApasbacLoading(),
              error: (e, _) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(adminAnimalsProvider),
                      child: const Text('Tentar carregar animais novamente'))),
              data: (all) {
                final animals = all
                    .where((a) => a.isAdopted && a.adoptedById != null)
                    .toList();
                if (animals.isEmpty) {
                  return const Center(
                      child: Text(
                          'Vincule um tutor ao animal na aba Adoções primeiro.'));
                }
                return ListView(padding: const EdgeInsets.all(20), children: [
                  DropdownButtonFormField<int>(
                      initialValue: animalId,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Animal adotado'),
                      items: animals
                          .map((a) => DropdownMenuItem(
                              value: a.id, child: Text('${a.name} (#${a.id})')))
                          .toList(),
                      onChanged:
                          saving ? null : (v) => setState(() => animalId = v)),
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          'O monitoramento será atribuído ao tutor vinculado ao animal.')),
                  TextField(
                      controller: notes,
                      enabled: !saving,
                      decoration:
                          const InputDecoration(labelText: 'Observações'),
                      maxLines: 3),
                  if (error != null)
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 20),
                  FilledButton(
                      onPressed: saving || animalId == null
                          ? null
                          : () async {
                              final animal =
                                  animals.firstWhere((a) => a.id == animalId);
                              setState(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                await ref
                                    .read(monitoringServiceProvider)
                                    .createMonitoring(
                                        animalId: animal.id,
                                        tutorId: animal.adoptedById!,
                                        notes: notes.text);
                                ref.invalidate(myMonitoringsProvider);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Monitoramento criado.')));
                                  Navigator.pop(context);
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() =>
                                      error = 'Não foi possível criar: $e');
                                }
                              } finally {
                                if (mounted) setState(() => saving = false);
                              }
                            },
                      child:
                          Text(saving ? 'Criando...' : 'Criar monitoramento')),
                ]);
              },
            ),
      ));
}
