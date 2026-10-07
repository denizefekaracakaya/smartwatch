import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/messages.dart';
import '../../state/auth_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().api.resetPassword(widget.email, _code.text, _password.text);
      if (!mounted) return;
      showSnack(context, 'Şifren güncellendi. Yeni şifrenle giriş yapabilirsin.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni şifre belirle')),
      body: Form(
        key: _form,
        child: FormPage(children: [
          Text('Bir hesap ${widget.email} ile kayıtlıysa 6 haneli kod gönderildi. Kod 15 dakika geçerlidir.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Kod', prefixIcon: Icon(Icons.pin_outlined)),
            validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : '6 haneli kodu girin.',
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Yeni şifre',
              helperText: 'En az 10 karakter, harf ve rakam içermeli',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: validatePassword,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(label: 'Şifreyi güncelle', busy: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
