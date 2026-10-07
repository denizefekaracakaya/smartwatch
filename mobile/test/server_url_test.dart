import 'dart:convert';

import 'package:efetufe/api/api_client.dart';
import 'package:efetufe/main.dart';
import 'package:efetufe/state/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  test('parseServerUrl normalises and validates addresses', () {
    expect(ApiClient.parseServerUrl('192.168.1.8:8000').toString(), 'http://192.168.1.8:8000');
    expect(ApiClient.parseServerUrl(' https://api.example.com/ ').toString(), 'https://api.example.com');
    expect(ApiClient.parseServerUrl('https://example.com/efetufe').toString(), 'https://example.com/efetufe');
    for (final bad in ['', '   ', 'ftp://x.com', 'http://', 'http://x.com/?a=1', 'javascript:alert(1)']) {
      expect(ApiClient.parseServerUrl(bad), isNull, reason: bad);
    }
  });

  test('switching servers drops the session and routes requests to the new host', () async {
    final hosts = <String>[];
    final store = MemoryTokenStore()..token = 'old-refresh';
    final api = ApiClient(
      baseUrl: 'http://10.0.2.2:8000',
      tokenStore: store,
      httpClient: MockClient((req) async {
        hosts.add('${req.url.host}:${req.url.port}${req.url.path}');
        return http.Response.bytes(utf8.encode(jsonEncode({'detail': 'ok'})), 202);
      }),
    );
    await api.setBaseUrl('192.168.1.8:8000');
    expect(store.token, isNull);
    expect(api.baseUrl, 'http://192.168.1.8:8000');
    await api.forgotPassword('a@b.co');
    expect(hosts, ['192.168.1.8:8000/api/v1/auth/forgot-password']);
    expect(() => api.setBaseUrl('not a url ://'), throwsArgumentError);
  });

  testWidgets('login screen lets the user change and persist the server address', (tester) async {
    final store = MemoryTokenStore();
    final auth = AuthState(ApiClient(baseUrl: 'http://10.0.2.2:8000', tokenStore: store))
      ..status = AuthStatus.signedOut;
    await tester.pumpWidget(ChangeNotifierProvider.value(value: auth, child: const MaterialApp(home: AuthGate())));

    expect(find.text('Sunucu: http://10.0.2.2:8000'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('server-button')));
    await tester.tap(find.byKey(const Key('server-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('server-field')), 'ftp://nope');
    await tester.tap(find.byKey(const Key('server-save')));
    await tester.pump();
    expect(find.text('Geçerli bir http(s) adresi girin.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('server-field')), '192.168.1.8:8000');
    await tester.tap(find.byKey(const Key('server-save')));
    await tester.pumpAndSettle();
    expect(find.text('Sunucu: http://192.168.1.8:8000'), findsOneWidget);
    expect(store.serverUrl, 'http://192.168.1.8:8000');
  });
}
