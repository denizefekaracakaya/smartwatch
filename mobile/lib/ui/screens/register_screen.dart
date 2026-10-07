import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/messages.dart';
import '../../state/auth_state.dart';
import '../widgets/common.dart';
import 'verify_pending_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().register(_email.text, _password.text, _name.text);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => VerifyPendingScreen(email: _email.text.trim(), justRegistered: true),
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesap oluştur')),
      body: Form(
        key: _form,
        child: FormPage(children: [
          TextFormField(
            key: const Key('register-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Görünen ad', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Bir ad girin.'
                : (v.trim().length > 80 ? 'En fazla 80 karakter.' : null),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('register-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.mail_outline)),
            validator: validateEmail,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('register-password'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Şifre',
              helperText: 'En az 10 karakter, harf ve rakam içermeli',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: validatePassword,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('register-confirm'),
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Şifre (tekrar)', prefixIcon: Icon(Icons.lock_outline)),
            validator: (v) => v != _password.text ? 'Şifreler eşleşmiyor.' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(label: 'Kayıt ol', busy: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
