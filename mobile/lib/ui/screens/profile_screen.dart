import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/messages.dart';
import '../../state/auth_state.dart';
import '../theme.dart';
import '../widgets/add_to_playlist_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // Player and library cleanup happens in AuthGate when the session ends.
  Future<void> _logout(BuildContext context) => context.read<AuthState>().logout();

  Future<void> _rename(BuildContext context) async {
    final auth = context.read<AuthState>();
    final name = await promptText(
      context,
      title: 'Görünen ad',
      label: 'Ad',
      initial: auth.user?.displayName ?? '',
      maxLength: 80,
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await auth.updateDisplayName(name);
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthState>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(
            child: Text((user?.displayName.isNotEmpty ?? false) ? user!.displayName[0].toUpperCase() : '?'),
          ),
          title: Text(user?.displayName ?? ''),
          subtitle: Text(user?.email ?? ''),
          trailing: IconButton(
            tooltip: 'Adı düzenle',
            icon: const Icon(Icons.edit),
            onPressed: () => _rename(context),
          ),
        ),
        ListTile(
          leading: Icon(user?.emailVerified ?? false ? Icons.verified : Icons.error_outline),
          title: Text(user?.emailVerified ?? false ? 'E-posta doğrulandı' : 'E-posta doğrulanmadı'),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Şifreyi değiştir'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Çıkış yap'),
          onTap: () => _logout(context),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
          title: Text('Hesabı sil', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => _deleteAccount(context),
        ),
      ]),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hesabın silinsin mi?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Hesabın ve tüm çalma listelerin kalıcı olarak silinecek. Onaylamak için şifreni gir.'),
          TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.of(c).pop(controller.text), child: const Text('Kalıcı olarak sil')),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty || !context.mounted) return;
    try {
      await context.read<AuthState>().deleteAccount(password);
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e));
    }
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthState>().changePassword(_current.text, _next.text);
      if (!mounted) return;
      showSnack(context, 'Şifren güncellendi. Diğer cihazlardaki oturumlar kapatıldı.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Şifreyi değiştir')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          TextFormField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mevcut şifre'),
            validator: (v) => (v ?? '').isEmpty ? 'Mevcut şifreni gir.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Yeni şifre', helperText: 'En az 10 karakter, harf ve rakam'),
            validator: validatePassword,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Güncelle')),
        ]),
      ),
    );
  }
}
