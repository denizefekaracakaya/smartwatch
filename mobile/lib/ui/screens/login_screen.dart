import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/messages.dart';
import '../../state/auth_state.dart';
import '../widgets/common.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'verify_pending_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
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
      await context.read<AuthState>().login(_email.text, _password.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'email_not_verified') {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => VerifyPendingScreen(email: _email.text.trim()),
        ));
      } else {
        setState(() => _error = errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Form(
        key: _form,
        child: FormPage(children: [
          Icon(Icons.graphic_eq, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Efetüfe', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('Müziğin bulutta, cebin rahat.', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 32),
          TextFormField(
            key: const Key('login-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.mail_outline)),
            validator: validateEmail,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('login-password'),
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Şifre',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Şifrenizi girin.' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          BusyButton(label: 'Giriş yap', busy: _busy, onPressed: _submit),
          TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const ForgotPasswordScreen())),
            child: const Text('Şifremi unuttum'),
          ),
          const Divider(height: 32),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen())),
            child: const Text('Hesap oluştur'),
          ),
        ]),
      ),
    );
  }
}
