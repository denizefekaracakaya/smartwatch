import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/messages.dart';
import '../../state/auth_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Shown after registration or when an unverified account tries to log in.
class VerifyPendingScreen extends StatefulWidget {
  const VerifyPendingScreen({super.key, required this.email, this.justRegistered = false});

  final String email;
  final bool justRegistered;

  @override
  State<VerifyPendingScreen> createState() => _VerifyPendingScreenState();
}

class _VerifyPendingScreenState extends State<VerifyPendingScreen> {
  bool _busy = false;

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthState>().api.resendVerification(widget.email);
      if (mounted) showSnack(context, 'Doğrulama e-postası yeniden gönderildi.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('E-postanı doğrula')),
      body: FormPage(children: [
        Icon(Icons.mark_email_unread_outlined, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          widget.justRegistered ? 'Hesabın oluşturuldu!' : 'E-posta adresin henüz doğrulanmadı',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          '${widget.email} adresine bir doğrulama bağlantısı gönderdik. '
          'Bağlantıya tıkladıktan sonra giriş yapabilirsin.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        BusyButton(label: 'Giriş ekranına dön', busy: false, onPressed: () => Navigator.of(context).pop()),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _resend,
          child: const Text('E-postayı tekrar gönder'),
        ),
      ]),
    );
  }
}
