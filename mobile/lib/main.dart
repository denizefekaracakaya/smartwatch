import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'config.dart';
import 'state/auth_state.dart';
import 'state/library_state.dart';
import 'state/playback_controller.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.efetufe.efetufe.playback',
    androidNotificationChannelName: 'Müzik çalma',
    androidNotificationOngoing: true,
  );
  final store = SecureTokenStore();
  // A server chosen in the app (login screen -> "Sunucu") wins over the build-time default.
  final saved = await store.readServerUrl();
  final baseUrl = (saved != null && ApiClient.parseServerUrl(saved) != null) ? saved : AppConfig.apiBaseUrl;
  final api = ApiClient(baseUrl: baseUrl, tokenStore: store);
  runApp(EfetufeApp(api: api));
}

class EfetufeApp extends StatelessWidget {
  const EfetufeApp({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState(api)..bootstrap()),
        ChangeNotifierProvider(create: (_) => LibraryState(api)),
        ChangeNotifierProvider(create: (_) => PlaybackController(api)),
      ],
      child: MaterialApp(
        title: 'Efetüfe',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AuthGate(),
      ),
    );
  }
}

/// Routes between splash, auth flow and the main app based on [AuthState].
///
/// Also cleans up per-user state whenever the session ends — including when it expires on its own
/// (refresh token revoked elsewhere), not only on an explicit logout.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthStatus? _previous;

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthState>().status;
    if (_previous == AuthStatus.signedIn && status == AuthStatus.signedOut) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<PlaybackController>().stop();
        context.read<LibraryState>().clear();
      });
    }
    _previous = status;
    switch (status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut:
        return const LoginScreen();
      case AuthStatus.signedIn:
        return const HomeShell();
    }
  }
}
