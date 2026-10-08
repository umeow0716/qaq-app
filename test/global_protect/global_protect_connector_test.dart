import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_connector.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_models.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  bool closed = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(options);
    if (body != null) await body.drain<void>();
    return respond(options);
  }

  @override
  void close({bool force = false}) => closed = true;
}

const _prelogin =
    '<prelogin-response><status>Success</status><region>TW</region>'
    '<username-label>Account</username-label><password-label>Password</password-label></prelogin-response>';
const _portal =
    '<response><portal-name>NTUT</portal-name><portal-userauthcookie>test-cookie</portal-userauthcookie>'
    '<policy><gateways><external><list>'
    '<entry name="vpn-low.example"><priority-rule><entry name="Any"><priority>10</priority></entry></priority-rule></entry>'
    '<entry name="vpn-high.example"><priority-rule><entry name="TW"><priority>1</priority></entry></priority-rule></entry>'
    '</list></external></gateways></policy></response>';
String _login() {
  final args = List.filled(16, '(null)');
  args[1] = 'test-auth-cookie';
  args[3] = 'NTUT';
  args[4] = 'test-user';
  args[12] = 'tunnel';
  args[15] = '10.0.0.2';
  return '<jnlp><application-desc>${args.map((a) => '<argument>$a</argument>').join()}</application-desc></jnlp>';
}

String _config() {
  String key(String tag) => '<$tag><bits>128</bits><val>${'00' * 16}</val></$tag>';
  return '<response><ip-address>10.0.0.2</ip-address><mtu>1400</mtu><gw-address>192.0.2.1</gw-address>'
      '<dns><member>10.0.0.1</member></dns><access-routes><member>10.0.0.0/8</member></access-routes>'
      '<ipsec><ipsec-mode>esp</ipsec-mode><udp-port>4501</udp-port><enc-algo>aes-128-cbc</enc-algo><hmac-algo>sha1</hmac-algo>'
      '<c2s-spi>0x12345678</c2s-spi><s2c-spi>87654321</s2c-spi>'
      '${key('ekey-c2s')}${key('ekey-s2c')}${key('akey-c2s')}${key('akey-s2c')}</ipsec></response>';
}

void main() {
  late GlobalProtectConnector connector;
  late _Adapter adapter;
  void respond(ResponseBody Function(RequestOptions) handler) {
    adapter = _Adapter(handler);
    final client = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (_) => true,
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    client.httpClientAdapter = adapter;
    connector = GlobalProtectConnector(portal: Uri.parse('https://portal.example'), dio: client);
  }

  final session = GlobalProtectSession(values: {'authcookie': 'test-auth-cookie', 'user': 'test-user'});
  final gateway = Uri.parse('https://gateway.example');
  tearDown(() => connector.close());

  test('prelogin parses portal and gateway forms', () async {
    respond((_) => ResponseBody.fromString(_prelogin, 200));
    final result = await connector.prelogin();
    expect(result.region, 'TW');
    expect(result.requiresSaml, isFalse);
    expect(adapter.requests.single.uri.path, '/global-protect/prelogin.esp');
    await connector.prelogin(server: gateway, gateway: true);
    expect(adapter.requests.last.uri.path, '/ssl-vpn/prelogin.esp');
    expect(adapter.requests.last.uri.host, 'gateway.example');
  });
  test('prelogin rejects protocol errors and malformed XML', () async {
    respond(
      (_) => ResponseBody.fromString(
        '<prelogin-response><status>Error</status><msg>Denied</msg></prelogin-response>',
        200,
      ),
    );
    await expectLater(connector.prelogin(), throwsStateError);
    connector.close();
    respond((_) => ResponseBody.fromString('<broken', 200));
    await expectLater(connector.prelogin(), throwsFormatException);
  });
  test('GP auth does not manually follow unexpected HTTP redirects', () async {
    respond(
      (_) => ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://other.example/login'],
        },
      ),
    );
    await expectLater(connector.prelogin(), throwsA(isA<HttpException>()));
    expect(adapter.requests, hasLength(1));
  });
  test('authenticatePortal parses cookie and selects regional gateway priority', () async {
    respond((_) => ResponseBody.fromString(_portal, 200));
    final result = await connector.authenticatePortal(username: 'test-user', password: 'test-password', region: 'TW');
    expect(result.gateways.first.host, 'vpn-high.example');
    expect(result.portalUserAuthCookie, 'test-cookie');
    expect(adapter.requests.single.uri.path, '/global-protect/getconfig.esp');
  });
  test('authenticatePortal rejects an empty gateway list', () async {
    respond((_) => ResponseBody.fromString('<response><policy/></response>', 200));
    await expectLater(
      connector.authenticatePortal(username: 'test-user', password: 'test-password'),
      throwsFormatException,
    );
  });
  test('authenticateGateway parses JNLP session', () async {
    respond((_) => ResponseBody.fromString(_login(), 200));
    final result = await connector.authenticateGateway(
      gateway: gateway,
      username: 'test-user',
      password: 'test-password',
    );
    expect(result.authCookie, 'test-auth-cookie');
    expect(result.values['user'], 'test-user');
    expect(result.values['preferred-ip'], '10.0.0.2');
    expect(adapter.requests.single.uri.path, '/ssl-vpn/login.esp');
  });
  test('authenticateGateway rejects incomplete JNLP', () async {
    respond((_) => ResponseBody.fromString('<jnlp><argument>one</argument></jnlp>', 200));
    await expectLater(
      connector.authenticateGateway(gateway: gateway, username: 'test-user', password: 'test-password'),
      throwsFormatException,
    );
  });
  test('getTunnelConfig parses ESP keys, DNS, routes and byte order', () async {
    respond((_) => ResponseBody.fromString(_config(), 200));
    final result = await connector.getTunnelConfig(gateway: gateway, session: session);
    expect(result.ipAddress, '10.0.0.2');
    expect(result.dnsServers, ['10.0.0.1']);
    expect(result.includeRoutes, ['10.0.0.0/8']);
    expect(result.ipsec!.keyMaterial!.clientToServerSpi, 0x12345678);
    expect(result.ipsec!.keyMaterial!.serverToClientSpi, 0x87654321);
    expect(result.ipsec!.keyMaterial!.clientToServerEncryptionKey, hasLength(16));
  });
  for (final status in [512, 513]) {
    test('getTunnelConfig classifies HTTP $status', () async {
      respond((_) => ResponseBody.fromString('', status));
      await expectLater(
        connector.getTunnelConfig(gateway: gateway, session: session),
        throwsA(
          status == 512
              ? isA<GlobalProtectSessionRejectedException>()
              : isA<GlobalProtectClientCertificateRequiredException>(),
        ),
      );
    });
  }
  test('resumeWithSession rejects expired XML session before opening data channel', () async {
    respond(
      (_) => ResponseBody.fromString(
        '<response status="error"><error>Invalid authentication cookie</error></response>',
        200,
      ),
    );
    await expectLater(
      connector.resumeWithSession(gateway: gateway, session: session),
      throwsA(isA<GlobalProtectSessionRejectedException>()),
    );
    expect(adapter.requests, hasLength(1));
  });
  test('connectWithPassword refuses unsupported SAML without sending password', () async {
    respond(
      (_) => ResponseBody.fromString(
        '<prelogin-response><status>Success</status><saml-auth-method>POST</saml-auth-method>'
        '<saml-request>test-saml-request</saml-request></prelogin-response>',
        200,
      ),
    );
    await expectLater(
      connector.connectWithPassword(username: 'test-user', password: 'test-password'),
      throwsUnsupportedError,
    );
    expect(adapter.requests, hasLength(1));
  });
  test('connectWithPassword refuses missing ESP material after auth', () async {
    respond(
      (r) => ResponseBody.fromString(switch (r.uri.path) {
        '/global-protect/prelogin.esp' || '/ssl-vpn/prelogin.esp' => _prelogin,
        '/global-protect/getconfig.esp' => _portal,
        '/ssl-vpn/login.esp' => _login(),
        _ => '<response><ip-address>10.0.0.2</ip-address></response>',
      }, 200),
    );
    await expectLater(
      connector.connectWithPassword(username: 'test-user', password: 'test-password'),
      throwsUnsupportedError,
    );
    expect(adapter.requests.map((r) => r.uri.path), [
      '/global-protect/prelogin.esp',
      '/global-protect/getconfig.esp',
      '/ssl-vpn/prelogin.esp',
      '/ssl-vpn/login.esp',
      '/ssl-vpn/getconfig.esp',
    ]);
  });
  test('close releases owned Dio adapter', () {
    respond((_) => ResponseBody.fromString(_prelogin, 200));
    connector.close();
    expect(adapter.closed, isTrue);
  });
}
