import 'dart:convert';

import 'package:efetufe/api/api_client.dart';
import 'package:efetufe/main.dart';
import 'package:efetufe/state/auth_state.dart';
import 'package:efetufe/ui/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

Widget _app(AuthState auth) => ChangeNotifierProvider.value(
      value: auth,
      child: const MaterialApp(home: AuthGate()),
    );

void main() {
  testWidgets('login form validates input before calling the API', (tester) async {
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((_) async {
        calls++;
        return _json({}, 500);
      }),
    );
    final auth = AuthState(api)..status = AuthStatus.signedOut;
    await tester.pumpWidget(_app(auth));

    await tester.tap(find.text('Giriş yap'));
    await tester.pump();
    expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);
    expect(find.text('Şifrenizi girin.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('wrong credentials show a Turkish error', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((_) async => _json({'detail': 'x', 'code': 'invalid_credentials'}, 401)),
    );
    final auth = AuthState(api)..status = AuthStatus.signedOut;
    await tester.pumpWidget(_app(auth));

    await tester.enterText(find.byKey(const Key('login-email')), 'ada@example.com');
    await tester.enterText(find.byKey(const Key('login-password')), 'WrongPass123');
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta veya şifre hatalı.'), findsOneWidget);
    expect(auth.status, AuthStatus.signedOut);
  });

  testWidgets('unverified account is sent to the verification screen', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((_) async => _json({'detail': 'x', 'code': 'email_not_verified'}, 403)),
    );
    final auth = AuthState(api)..status = AuthStatus.signedOut;
    await tester.pumpWidget(_app(auth));

    await tester.enterText(find.byKey(const Key('login-email')), 'new@example.com');
    await tester.enterText(find.byKey(const Key('login-password')), 'CorrectHorse42');
    await tester.tap(find.text('Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta adresin henüz doğrulanmadı'), findsOneWidget);
    expect(find.textContaining('new@example.com'), findsOneWidget);
  });

  testWidgets('registration sends normalised data and shows the verify screen', (tester) async {
    Map<String, dynamic>? body;
    final api = ApiClient(
      baseUrl: 'http://api.test',
      tokenStore: MemoryTokenStore(),
      httpClient: MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'id': 1}, 201);
      }),
    );
    final auth = AuthState(api)..status = AuthStatus.signedOut;
    await tester.pumpWidget(_app(auth));
    await tester.tap(find.text('Hesap oluştur'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('register-name')), '  Ada  ');
    await tester.enterText(find.byKey(const Key('register-email')), ' ada@example.com ');
    await tester.enterText(find.byKey(const Key('register-password')), 'weak');
    await tester.enterText(find.byKey(const Key('register-confirm')), 'weak');
    await tester.tap(find.text('Kayıt ol'));
    await tester.pump();
    expect(find.text('Şifre en az 10 karakter olmalı.'), findsOneWidget);
    expect(body, isNull);

    await tester.enterText(find.byKey(const Key('register-password')), 'CorrectHorse42');
    await tester.enterText(find.byKey(const Key('register-confirm')), 'CorrectHorse42');
    await tester.ensureVisible(find.text('Kayıt ol'));
    await tester.tap(find.text('Kayıt ol'));
    await tester.pumpAndSettle();
    expect(body, {'email': 'ada@example.com', 'password': 'CorrectHorse42', 'display_name': 'Ada'});
    expect(find.text('Hesabın oluşturuldu!'), findsOneWidget);
  });

  testWidgets('AuthGate shows a spinner while the session is being restored', (tester) async {
    final api = ApiClient(baseUrl: 'http://api.test', tokenStore: MemoryTokenStore());
    await tester.pumpWidget(_app(AuthState(api)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
