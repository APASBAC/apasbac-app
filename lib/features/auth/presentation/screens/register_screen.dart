import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cpfCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).register(
            fullName: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            cpf: _cpfCtrl.text.replaceAll(RegExp(r'\D'), ''),
            password: _passCtrl.text,
            confirmPassword: _confirmCtrl.text,
          );
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? 'Erro ao cadastrar';
      setState(() => _error = msg is List ? msg.join(', ') : msg.toString());
    } catch (e) {
      setState(() => _error = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(_nameCtrl, 'Nome completo', Icons.person_outlined,
                    validator: (v) => v == null || v.trim().length < 3 ? 'Nome inválido' : null),
                const SizedBox(height: 16),
                _field(_emailCtrl, 'E-mail', Icons.email_outlined,
                    type: TextInputType.emailAddress,
                    validator: (v) => v == null || !v.contains('@') ? 'E-mail inválido' : null),
                const SizedBox(height: 16),
                _field(_phoneCtrl, 'Telefone (+55 46 99999-9999)', Icons.phone_outlined,
                    type: TextInputType.phone,
                    validator: (v) => v == null || v.length < 10 ? 'Telefone inválido' : null),
                const SizedBox(height: 16),
                _field(_cpfCtrl, 'CPF (apenas números)', Icons.badge_outlined,
                    type: TextInputType.number,
                    validator: (v) {
                      final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                      return digits.length != 11 ? 'CPF deve ter 11 dígitos' : null;
                    }),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) return 'Mínimo 8 caracteres';
                    if (!v.contains(RegExp(r'[A-Z]'))) return 'Precisa de letra maiúscula';
                    if (!v.contains(RegExp(r'[0-9]'))) return 'Precisa de número';
                    if (!v.contains(RegExp(r'[!@#\$%^&*]'))) return 'Precisa de caractere especial';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar senha',
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                  validator: (v) => v != _passCtrl.text ? 'Senhas não coincidem' : null,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
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
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Criar conta', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      validator: validator,
    );
  }
}
