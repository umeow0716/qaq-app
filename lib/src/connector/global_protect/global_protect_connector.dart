import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'global_protect_transport.dart';
import 'global_protect_esp_transport.dart';
import 'global_protect_models.dart';

typedef GlobalProtectConnectorTrace = void Function(String message);

class GlobalProtectSessionRejectedException implements Exception {
  const GlobalProtectSessionRejectedException(this.reason, {this.statusCode});

  final String reason;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'GlobalProtect cached session was rejected: $reason'
      : 'GlobalProtect cached session was rejected (HTTP $statusCode): $reason';
}

class GlobalProtectClientCertificateRequiredException implements Exception {
  const GlobalProtectClientCertificateRequiredException(this.reason, {this.statusCode});

  final String reason;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'GlobalProtect requires a valid client certificate: $reason'
      : 'GlobalProtect requires a valid client certificate (HTTP $statusCode): $reason';
}

class GlobalProtectConnector {
  GlobalProtectConnector({Uri? portal, HttpClient? httpClient, this.computerName = 'qaq-android'})
    : portal = portal ?? Uri.parse('https://vpn.ntut.edu.tw'),
      _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const String userAgent = 'PAN GlobalProtect';
  static const String clientOs = 'Android';
  static const String osVersion = 'android';
  static const String clientVersion = '4100';
  static const String fallbackAppVersion = '6.3.0-33';

  final Uri portal;
  final HttpClient _httpClient;
  final String computerName;

  Future<GlobalProtectPreloginResult> prelogin({Uri? server, bool gateway = false}) async {
    final target = server ?? portal;
    final path = gateway ? '/ssl-vpn/prelogin.esp' : '/global-protect/prelogin.esp';
    final uri = target.replace(
      path: path,
      queryParameters: const {'tmp': 'tmp', 'clientVer': clientVersion, 'clientos': clientOs},
    );
    final xml = await _postForm(uri, const {'cas-support': 'yes'});
    final root = _parseXml(xml).rootElement;

    if (root.name.local != 'prelogin-response') {
      throw FormatException('Unexpected GlobalProtect prelogin response: ${root.name.local}');
    }
    _throwIfPreloginError(root);

    return GlobalProtectPreloginResult(
      authenticationMessage: _text(root, 'authentication-message'),
      usernameLabel: _text(root, 'username-label'),
      passwordLabel: _text(root, 'password-label'),
      samlMethod: _text(root, 'saml-auth-method'),
      samlRequest: _text(root, 'saml-request'),
      region: _text(root, 'region'),
    );
  }

  Future<GlobalProtectPortalResult> authenticatePortal({
    required String username,
    required String password,
    String? region,
  }) async {
    final xml = await _postForm(
      portal.replace(path: '/global-protect/getconfig.esp', query: null),
      _loginForm(server: portal, username: username, password: password),
    );
    final root = _parseXml(xml).rootElement;
    _throwIfResponseError(root);

    final gateways = _parseGateways(root, region: region);
    if (gateways.isEmpty) {
      throw const FormatException('GlobalProtect portal returned no gateway servers.');
    }

    return GlobalProtectPortalResult(
      gateways: gateways,
      portalName: _text(root, 'portal-name'),
      portalUserAuthCookie: _nonEmptyCookie(_text(root, 'portal-userauthcookie')),
      portalPrelogonUserAuthCookie: _nonEmptyCookie(_text(root, 'portal-prelogonuserauthcookie')),
      appVersion: _text(root, 'version'),
    );
  }

  Future<GlobalProtectSession> authenticateGateway({
    required Uri gateway,
    required String username,
    required String password,
    String? portalUserAuthCookie,
    String? portalPrelogonUserAuthCookie,
  }) async {
    final form = _loginForm(
      server: gateway,
      username: username,
      password: password,
      portalUserAuthCookie: portalUserAuthCookie,
      portalPrelogonUserAuthCookie: portalPrelogonUserAuthCookie,
    );
    final xml = await _postForm(gateway.replace(path: '/ssl-vpn/login.esp', query: null), form);
    final root = _parseXml(xml).rootElement;
    _throwIfResponseError(root);
    return _parseLoginSession(root);
  }

  Future<GlobalProtectTunnelConfig> getTunnelConfig({
    required Uri gateway,
    required GlobalProtectSession session,
    String? appVersion,
  }) async {
    final form = <String, String>{
      'client-type': '1',
      'protocol-version': 'p1',
      'internal': 'no',
      'app-version': appVersion ?? fallbackAppVersion,
      'ipv6-support': 'no',
      'clientos': clientOs,
      'os-version': osVersion,
      'hmac-algo': 'sha1,md5,sha256',
      'enc-algo': 'aes-128-cbc,aes-256-cbc',
      ...session.values,
    };
    final xml = await _postForm(
      gateway.replace(path: '/ssl-vpn/getconfig.esp', query: null),
      form,
      classifySessionResumeFailure: true,
    );
    final root = _parseXml(xml).rootElement;
    _throwIfResponseError(root, classifySessionResumeFailure: true);
    return _parseTunnelConfig(root);
  }

  Future<GlobalProtectConnection> resumeWithSession({
    required Uri gateway,
    required GlobalProtectSession session,
    String? appVersion,
    GlobalProtectConnectorTrace? trace,
    GlobalProtectTransportTrace? transportTrace,
  }) async {
    trace?.call('resuming cached GP session -> ${gateway.host}');
    final config = await getTunnelConfig(gateway: gateway, session: session, appVersion: appVersion);
    trace?.call(
      'cached session accepted; ip=${config.ipAddress ?? '-'} mtu=${config.mtu ?? '-'} '
      'dns=${config.dnsServers.join(',')}',
    );

    final transport = await _openEspTransport(
      gateway: gateway,
      config: config,
      trace: trace,
      transportTrace: transportTrace,
    );

    return GlobalProtectConnection(gateway: gateway, session: session, config: config, transport: transport);
  }

  Future<GlobalProtectConnection> connectWithPassword({
    required String username,
    required String password,
    String? gatewayHost,
    GlobalProtectConnectorTrace? trace,
    GlobalProtectTransportTrace? transportTrace,
  }) async {
    trace?.call('portal prelogin -> ${portal.host}');
    final portalPrelogin = await prelogin();
    trace?.call('portal prelogin ok; saml=${portalPrelogin.requiresSaml}');
    if (portalPrelogin.requiresSaml) {
      throw UnsupportedError(
        'GlobalProtect portal requires SAML authentication. WebView SAML handoff is not implemented yet.',
      );
    }

    trace?.call('portal password authentication');
    final portalResult = await authenticatePortal(
      username: username,
      password: password,
      region: portalPrelogin.region,
    );
    trace?.call('portal authentication ok; gateways=${portalResult.gateways.length}');
    final selected = gatewayHost == null
        ? portalResult.gateways.first
        : portalResult.gateways.firstWhere(
            (item) => item.host == gatewayHost,
            orElse: () => GlobalProtectGateway(host: gatewayHost),
          );
    final gateway = _gatewayUri(selected.host);
    trace?.call('gateway selected -> ${gateway.host}');

    trace?.call('gateway prelogin');
    final gatewayPrelogin = await prelogin(server: gateway, gateway: true);
    trace?.call('gateway prelogin ok; saml=${gatewayPrelogin.requiresSaml}');
    if (gatewayPrelogin.requiresSaml &&
        portalResult.portalUserAuthCookie == null &&
        portalResult.portalPrelogonUserAuthCookie == null) {
      throw UnsupportedError(
        'GlobalProtect gateway requires SAML authentication. WebView SAML handoff is not implemented yet.',
      );
    }

    trace?.call('gateway password/cookie authentication');
    final session = await authenticateGateway(
      gateway: gateway,
      username: username,
      password: password,
      portalUserAuthCookie: portalResult.portalUserAuthCookie,
      portalPrelogonUserAuthCookie: portalResult.portalPrelogonUserAuthCookie,
    );
    trace?.call('gateway authentication ok');

    trace?.call('requesting tunnel config');
    final config = await getTunnelConfig(gateway: gateway, session: session, appVersion: portalResult.appVersion);
    trace?.call(
      'tunnel config ok; ip=${config.ipAddress ?? '-'} mtu=${config.mtu ?? '-'} '
      'dns=${config.dnsServers.join(',')}',
    );

    final transport = await _openEspTransport(
      gateway: gateway,
      config: config,
      trace: trace,
      transportTrace: transportTrace,
    );

    return GlobalProtectConnection(gateway: gateway, session: session, config: config, transport: transport);
  }

  Future<GlobalProtectTransport> _openEspTransport({
    required Uri gateway,
    required GlobalProtectTunnelConfig config,
    GlobalProtectConnectorTrace? trace,
    GlobalProtectTransportTrace? transportTrace,
  }) async {
    final ipsec = config.ipsec;
    if (ipsec == null || !ipsec.hasCompleteNegotiationMaterial || ipsec.keyMaterial == null) {
      throw UnsupportedError('GlobalProtect gateway did not provide complete ESP-over-UDP negotiation material.');
    }

    trace?.call(
      'opening ESP data channel; udpPort=${ipsec.udpPort ?? '-'} '
      'enc=${ipsec.encryptionAlgorithm ?? '-'} hmac=${ipsec.authenticationAlgorithm ?? '-'}',
    );
    final esp = await GlobalProtectEspTransport.connect(gateway: gateway, config: config, trace: transportTrace);
    trace?.call('ESP data channel connected');
    return esp;
  }

  void close() => _httpClient.close(force: true);

  Map<String, String> _loginForm({
    required Uri server,
    required String username,
    required String password,
    String? portalUserAuthCookie,
    String? portalPrelogonUserAuthCookie,
  }) => {
    'jnlpReady': 'jnlpReady',
    'ok': 'Login',
    'direct': 'yes',
    'clientVer': clientVersion,
    'prot': 'https:',
    'internal': 'no',
    'ipv6-support': 'no',
    'clientos': clientOs,
    'os-version': osVersion,
    'server': server.host,
    'computer': computerName,
    'portal-userauthcookie': ?portalUserAuthCookie,
    'portal-prelogonuserauthcookie': ?portalPrelogonUserAuthCookie,
    'user': username,
    'passwd': password,
  };

  Future<String> _postForm(Uri uri, Map<String, String> form, {bool classifySessionResumeFailure = false}) async {
    final request = await _httpClient.postUrl(uri);
    request.headers
      ..set(HttpHeaders.userAgentHeader, userAgent)
      ..contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    request.write(Uri(queryParameters: form).query);

    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (classifySessionResumeFailure) {
        if (response.statusCode == 512) {
          throw GlobalProtectSessionRejectedException(
            _sessionFailureReason(body, fallback: 'Invalid authentication cookie'),
            statusCode: response.statusCode,
          );
        }
        if (response.statusCode == 513) {
          throw GlobalProtectClientCertificateRequiredException(
            _sessionFailureReason(body, fallback: 'Valid client certificate is required'),
            statusCode: response.statusCode,
          );
        }
      }
      throw HttpException('GlobalProtect request failed with HTTP ${response.statusCode}: $body', uri: uri);
    }
    return body;
  }

  XmlDocument _parseXml(String source) {
    try {
      return XmlDocument.parse(source);
    } catch (error) {
      throw FormatException('Invalid GlobalProtect XML response: $error');
    }
  }

  void _throwIfPreloginError(XmlElement root) {
    final status = _text(root, 'status');
    if (status != null && status.toLowerCase() != 'success') {
      throw StateError(_text(root, 'msg') ?? 'GlobalProtect prelogin failed: $status');
    }
  }

  void _throwIfResponseError(XmlElement root, {bool classifySessionResumeFailure = false}) {
    if (root.name.local != 'response') return;

    final status = (root.getAttribute('status') ?? _text(root, 'status'))?.trim();
    final isError = status != null && status.toLowerCase() != 'success';
    if (!isError && root.getAttribute('status') != 'error') return;

    final reason =
        _text(root, 'error') ?? _text(root, 'msg') ?? _text(root, 'message') ?? 'GlobalProtect request failed.';

    if (classifySessionResumeFailure) {
      if (_sessionRejectedReasons.contains(reason)) {
        throw GlobalProtectSessionRejectedException(reason);
      }
      if (reason == 'Valid client certificate is required') {
        throw GlobalProtectClientCertificateRequiredException(reason);
      }
    }

    throw StateError(reason);
  }

  String _sessionFailureReason(String body, {required String fallback}) {
    try {
      final root = _parseXml(body).rootElement;
      return _text(root, 'error') ?? _text(root, 'msg') ?? _text(root, 'message') ?? fallback;
    } on FormatException {
      final trimmed = body.trim();
      return trimmed.isEmpty ? fallback : trimmed;
    }
  }

  static const Set<String> _sessionRejectedReasons = {
    'Invalid authentication cookie',
    'Portal name not found',
    'Allow Automatic Restoration of SSL VPN is disabled',
  };

  GlobalProtectSession _parseLoginSession(XmlElement root) {
    if (root.name.local != 'jnlp') {
      throw FormatException('Unexpected GlobalProtect login response: ${root.name.local}');
    }
    final arguments = root.findAllElements('argument').map((element) => element.innerText.trim()).toList();
    if (arguments.length < 16) {
      throw FormatException('GlobalProtect login returned ${arguments.length} arguments; expected at least 16.');
    }

    final values = <String, String>{};
    void save(int index, String key) {
      if (index >= arguments.length) return;
      final value = arguments[index];
      if (value.isEmpty || value == '(null)' || value == '-1') return;
      values[key] = _safeDecode(value);
    }

    save(1, 'authcookie');
    save(3, 'portal');
    save(4, 'user');
    save(7, 'domain');
    save(15, 'preferred-ip');
    if (arguments.length > 18) save(18, 'preferred-ipv6');
    values['computer'] = computerName;

    if ((values['authcookie'] ?? '').isEmpty || (values['user'] ?? '').isEmpty) {
      throw const FormatException('GlobalProtect login response is missing user/authcookie.');
    }
    if (arguments.length > 12 && arguments[12].isNotEmpty && arguments[12] != 'tunnel') {
      throw FormatException('GlobalProtect returned unsupported connection type: ${arguments[12]}');
    }
    return GlobalProtectSession(values: values);
  }

  GlobalProtectTunnelConfig _parseTunnelConfig(XmlElement root) {
    if (root.name.local != 'response') {
      throw FormatException('Unexpected GlobalProtect config response: ${root.name.local}');
    }

    return GlobalProtectTunnelConfig(
      ipAddress: _text(root, 'ip-address'),
      ipv6Address: _text(root, 'ip-address-v6'),
      netmask: _text(root, 'netmask'),
      mtu: int.tryParse(_text(root, 'mtu') ?? ''),
      gatewayAddress: _text(root, 'gw-address'),
      dnsServers: _members(root, const {'dns', 'dns-v6'}),
      dnsSuffixes: _members(root, const {'dns-suffix'}),
      includeRoutes: _members(root, const {'access-routes', 'access-routes-v6'}),
      excludeRoutes: _members(root, const {'exclude-access-routes', 'exclude-access-routes-v6'}),
      ipsec: _parseIpsecConfig(root),
    );
  }

  GlobalProtectIpsecConfig? _parseIpsecConfig(XmlElement root) {
    final ipsec = root.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'ipsec')
        .firstOrNull;
    if (ipsec == null) return null;

    String? value(String name) {
      final element = ipsec.findElements(name).firstOrNull;
      final text = element?.innerText.trim();
      return text == null || text.isEmpty ? null : text;
    }

    Uint8List? keyBytes(String name) {
      final element = ipsec.findElements(name).firstOrNull;
      if (element == null) return null;
      final bitsText = element.findElements('bits').firstOrNull?.innerText.trim();
      final hexText = element.findElements('val').firstOrNull?.innerText.trim();
      final bits = int.tryParse(bitsText ?? '');
      if (bits == null || bits <= 0 || bits % 8 != 0 || hexText == null) return null;
      final normalized = hexText.replaceAll(RegExp(r'\s+'), '');
      if (normalized.length != bits ~/ 4 || normalized.length.isOdd) return null;
      final result = Uint8List(bits ~/ 8);
      for (var i = 0; i < result.length; i++) {
        final byte = int.tryParse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
        if (byte == null) return null;
        result[i] = byte;
      }
      return result;
    }

    int? spi(String name) {
      final text = value(name);
      if (text == null) return null;
      final normalized = text.toLowerCase().startsWith('0x') ? text.substring(2) : text;
      return int.tryParse(normalized, radix: 16);
    }

    final c2sSpi = spi('c2s-spi');
    final s2cSpi = spi('s2c-spi');
    final ekeyC2s = keyBytes('ekey-c2s');
    final ekeyS2c = keyBytes('ekey-s2c');
    final akeyC2s = keyBytes('akey-c2s');
    final akeyS2c = keyBytes('akey-s2c');
    final material =
        c2sSpi != null && s2cSpi != null && ekeyC2s != null && ekeyS2c != null && akeyC2s != null && akeyS2c != null
        ? GlobalProtectIpsecKeyMaterial(
            clientToServerSpi: c2sSpi,
            serverToClientSpi: s2cSpi,
            clientToServerEncryptionKey: ekeyC2s,
            serverToClientEncryptionKey: ekeyS2c,
            clientToServerAuthenticationKey: akeyC2s,
            serverToClientAuthenticationKey: akeyS2c,
          )
        : null;

    return GlobalProtectIpsecConfig(
      mode: value('ipsec-mode'),
      udpPort: int.tryParse(value('udp-port') ?? ''),
      encryptionAlgorithm: value('enc-algo'),
      authenticationAlgorithm: value('hmac-algo'),
      hasClientToServerSpi: c2sSpi != null,
      hasServerToClientSpi: s2cSpi != null,
      hasClientToServerEncryptionKey: ekeyC2s != null,
      hasServerToClientEncryptionKey: ekeyS2c != null,
      hasClientToServerAuthenticationKey: akeyC2s != null,
      hasServerToClientAuthenticationKey: akeyS2c != null,
      keyMaterial: material,
    );
  }

  List<GlobalProtectGateway> _parseGateways(XmlElement root, {String? region}) {
    XmlElement? policy;
    if (root.name.local == 'policy') {
      policy = root;
    } else {
      policy = root.findElements('policy').firstOrNull;
    }
    if (policy == null) return const [];

    final gateways = _child(_child(_child(policy, 'gateways'), 'external'), 'list');
    if (gateways == null) return const [];

    final result = <GlobalProtectGateway>[];
    for (final entry in gateways.findElements('entry')) {
      final host = entry.getAttribute('name');
      if (host == null || host.isEmpty) continue;
      result.add(
        GlobalProtectGateway(
          host: host,
          description: _text(entry, 'description'),
          priority: _gatewayPriority(entry, region),
        ),
      );
    }
    result.sort((a, b) => (a.priority ?? 1 << 30).compareTo(b.priority ?? 1 << 30));
    return result;
  }

  int? _gatewayPriority(XmlElement gateway, String? region) {
    if (region == null) return null;
    int? best;
    final rules = _child(gateway, 'priority-rule');
    if (rules == null) return null;
    for (final entry in rules.findElements('entry')) {
      final name = entry.getAttribute('name');
      if (name != region && name != 'Any') continue;
      final priority = int.tryParse(_text(entry, 'priority') ?? '');
      if (priority != null && (best == null || priority < best)) best = priority;
    }
    return best;
  }

  List<String> _members(XmlElement root, Set<String> parents) {
    final values = <String>[];
    for (final parent in root.descendants.whereType<XmlElement>()) {
      if (!parents.contains(parent.name.local)) continue;
      for (final member in parent.findElements('member')) {
        final value = member.innerText.trim();
        if (value.isNotEmpty && !values.contains(value)) values.add(value);
      }
    }
    return values;
  }

  XmlElement? _child(XmlElement? parent, String name) => parent?.findElements(name).firstOrNull;

  String? _text(XmlElement root, String name) {
    final element = root.descendants.whereType<XmlElement>().where((item) => item.name.local == name).firstOrNull;
    final value = element?.innerText.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _nonEmptyCookie(String? value) => value == null || value == 'empty' ? null : value;

  String _safeDecode(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } on FormatException {
      return value;
    }
  }

  Uri _gatewayUri(String host) {
    final uri = Uri.tryParse(host.contains('://') ? host : 'https://$host');
    if (uri == null || uri.host.isEmpty) throw FormatException('Invalid GlobalProtect gateway: $host');
    return uri.replace(scheme: 'https', path: '', query: null, fragment: null);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
