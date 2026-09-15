import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/theme/semantic_colors.dart';
import '../../../../core/widgets/app_content.dart';
import '../../../../providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: user == null
          ? const SizedBox.shrink()
          : AppContent(
              maxWidth: 600,
              child: _ProfileForm(key: ValueKey(user.id), user: user)),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  final UserModel user;
  const _ProfileForm({super.key, required this.user});
  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.fullName);
  late final _phone = TextEditingController(text: widget.user.phone);
  bool _saving = false, _sending = false, _sent = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = widget.user;
      final fullName = _name.text.trim(), phone = _phone.text.trim();
      await ref
          .read(userServiceProvider)
          .updateProfile(user.id, fullName: fullName, phone: phone);
      if (!mounted) return;
      ref
          .read(authProvider.notifier)
          .updateLocalProfile(fullName: fullName, phone: phone);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Perfil atualizado.')));
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Não foi possível salvar. Confira sua conexão e tente novamente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_sending || _sent) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).forgotPassword(widget.user.email);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted)
        setState(() =>
            _error = 'Não foi possível enviar o e-mail. Tente novamente.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final color = SemanticColors.role(user.role);
    return PopScope(
        canPop: !_saving && !_sending,
        child: SafeArea(
            child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
                child: CircleAvatar(
                    radius: 38,
                    backgroundColor: color.withValues(alpha: .12),
                    child: Text(
                        user.fullName.isEmpty
                            ? '?'
                            : user.fullName[0].toUpperCase(),
                        style: TextStyle(
                            color: color,
                            fontSize: 30,
                            fontWeight: FontWeight.w700)))),
            const SizedBox(height: 12),
            Text(user.fullName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Center(child: RoleBadge(role: user.role)),
            const SizedBox(height: 32),
            Text('Dados pessoais',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Mantenha seu nome e telefone atualizados.'),
            const SizedBox(height: 20),
            Form(
                key: _form,
                child: Column(children: [
                  TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          labelText: 'Nome completo',
                          prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Informe seu nome.'
                          : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _phone,
                      enabled: !_saving,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                          labelText: 'Telefone',
                          helperText: 'Inclua o DDD',
                          prefixIcon: Icon(Icons.phone_outlined)),
                      validator: (v) {
                        final length =
                            (v ?? '').replaceAll(RegExp(r'\D'), '').length;
                        return length < 10 || length > 13
                            ? 'Informe um telefone com DDD.'
                            : null;
                      }),
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.check),
                          label: Text(
                              _saving ? 'Salvando...' : 'Salvar alterações'))),
                ])),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 32),
            Text('Acesso e segurança',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: const Text('E-mail da conta'),
                    subtitle: Text(user.email))),
            const SizedBox(height: 12),
            Text(_sent
                ? 'Se o e-mail estiver cadastrado, você receberá as instruções. Confira também a caixa de spam.'
                : 'Para trocar sua senha, receba um link no e-mail da sua conta.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: _sending || _sent || _saving ? null : _resetPassword,
                icon: Icon(
                    _sent ? Icons.mark_email_read_outlined : Icons.lock_reset),
                label: Text(_sending
                    ? 'Enviando...'
                    : _sent
                        ? 'E-mail solicitado'
                        : 'Redefinir senha')),
            const SizedBox(height: 16),
            TextButton.icon(
                onPressed: _saving || _sending
                    ? null
                    : () => ref.read(authProvider.notifier).logout(),
                icon: const Icon(Icons.logout),
                label: const Text('Sair da conta')),
          ],
        )));
  }
}
