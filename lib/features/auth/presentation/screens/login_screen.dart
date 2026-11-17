import '../../../../core/widgets/app_content.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/apasbac_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../../../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _remember = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  /// Recupera a última escolha de "Lembrar de mim" e o e-mail lembrado.
  Future<void> _loadPreferences() async {
    try {
      final svc = ref.read(authServiceProvider);
      final remember = await svc.rememberMe();
      final email = remember ? await svc.lastEmail() : null;
      if (!mounted) return;
      setState(() {
        _remember = remember;
        if (email != null && _emailCtrl.text.isEmpty) _emailCtrl.text = email;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final error = await ref.read(authProvider.notifier).login(
            _emailCtrl.text.trim(),
            _passCtrl.text,
            remember: _remember,
          );
      if (error != null && mounted) {
        setState(() => _error = error);
      }
      // Navegação é feita automaticamente pelo router ao detectar usuário logado
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? 'Credenciais inválidas';
      setState(() => _error = msg is List ? msg.first : msg.toString());
    } catch (e) {
      setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notice = ref.watch(authNoticeProvider);
    return Scaffold(
      body: AppContent(
          maxWidth: 480,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ApasbacLogo(height: 110),
                      const SizedBox(height: 32),
                      Text('Bem-vindo de volta',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text('Entre para acompanhar seus animais.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 32),
                      if (notice != null && _error == null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Icon(Icons.lock_clock_outlined,
                                color: cs.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(notice)),
                          ]),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) => v == null || !v.contains('@')
                            ? 'E-mail inválido'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            tooltip:
                                _obscure ? 'Mostrar senha' : 'Ocultar senha',
                            icon: Icon(_obscure
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.length < 6
                            ? 'Senha muito curta'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _loading
                                ? null
                                : () => setState(() => _remember = !_remember),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Checkbox(
                                value: _remember,
                                onChanged: _loading
                                    ? null
                                    : (v) =>
                                        setState(() => _remember = v ?? true),
                              ),
                              const Flexible(child: Text('Lembrar de mim')),
                              const SizedBox(width: 8),
                            ]),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.push('/auth/forgot-password'),
                            child: const Text('Esqueci minha senha'),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          _remember
                              ? 'Você continua conectado neste celular.'
                              : 'Você sairá da conta ao fechar o aplicativo.',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: cs.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style:
                                        TextStyle(color: cs.onErrorContainer)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.cream),
                              )
                            : const Text('Entrar',
                                style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Não tem conta? '),
                          TextButton(
                            onPressed: () => context.push('/auth/register'),
                            child: const Text('Cadastre-se'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )),
    );
  }
}
