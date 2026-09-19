import 'dart:collection';
import 'dart:typed_data';

import 'global_protect_transport.dart';

class GlobalProtectPreloginResult {
  const GlobalProtectPreloginResult({
    this.authenticationMessage,
    this.usernameLabel,
    this.passwordLabel,
    this.samlMethod,
    this.samlRequest,
    this.region,
  });

  final String? authenticationMessage;
  final String? usernameLabel;
  final String? passwordLabel;
  final String? samlMethod;
  final String? samlRequest;
  final String? region;

  bool get requiresSaml => samlMethod != null && samlRequest != null;
}

class GlobalProtectGateway {
  const GlobalProtectGateway({required this.host, this.description, this.priority});

  final String host;
  final String? description;
  final int? priority;
}

class GlobalProtectPortalResult {
  const GlobalProtectPortalResult({
    required this.gateways,
    this.portalName,
    this.portalUserAuthCookie,
    this.portalPrelogonUserAuthCookie,
    this.appVersion,
  });

  final List<GlobalProtectGateway> gateways;
  final String? portalName;
  final String? portalUserAuthCookie;
  final String? portalPrelogonUserAuthCookie;
  final String? appVersion;
}

class GlobalProtectSession {
  GlobalProtectSession({required Map<String, String> values})
    : values = UnmodifiableMapView(Map<String, String>.from(values));

  final Map<String, String> values;

  String get user => values['user'] ?? '';
  String get authCookie => values['authcookie'] ?? '';
}

class GlobalProtectIpsecConfig {
  const GlobalProtectIpsecConfig({
    this.mode,
    this.udpPort,
    this.encryptionAlgorithm,
    this.authenticationAlgorithm,
    this.hasClientToServerSpi = false,
    this.hasServerToClientSpi = false,
    this.hasClientToServerEncryptionKey = false,
    this.hasServerToClientEncryptionKey = false,
    this.hasClientToServerAuthenticationKey = false,
    this.hasServerToClientAuthenticationKey = false,
    this.keyMaterial,
  });

  /// GlobalProtect data-channel mode, normally `esp-tunnel`.
  final String? mode;
  final int? udpPort;
  final String? encryptionAlgorithm;
  final String? authenticationAlgorithm;

  /// Capability flags. Secret SPI/key material, when complete, is retained only
  /// in memory via [keyMaterial] for the userspace ESP transport.
  final bool hasClientToServerSpi;
  final bool hasServerToClientSpi;
  final bool hasClientToServerEncryptionKey;
  final bool hasServerToClientEncryptionKey;
  final bool hasClientToServerAuthenticationKey;
  final bool hasServerToClientAuthenticationKey;

  /// Sensitive ESP material retained only in memory for the userspace data
  /// plane. Never log or persist this object. Its [toString] is redacted.
  final GlobalProtectIpsecKeyMaterial? keyMaterial;

  bool get hasSpis => hasClientToServerSpi && hasServerToClientSpi;

  bool get hasEncryptionKeys => hasClientToServerEncryptionKey && hasServerToClientEncryptionKey;

  bool get hasAuthenticationKeys => hasClientToServerAuthenticationKey && hasServerToClientAuthenticationKey;

  bool get hasCompleteNegotiationMaterial =>
      mode == 'esp-tunnel' &&
      udpPort != null &&
      encryptionAlgorithm != null &&
      authenticationAlgorithm != null &&
      hasSpis &&
      hasEncryptionKeys &&
      hasAuthenticationKeys;
}

class GlobalProtectIpsecKeyMaterial {
  GlobalProtectIpsecKeyMaterial({
    required this.clientToServerSpi,
    required this.serverToClientSpi,
    required Uint8List clientToServerEncryptionKey,
    required Uint8List serverToClientEncryptionKey,
    required Uint8List clientToServerAuthenticationKey,
    required Uint8List serverToClientAuthenticationKey,
  }) : clientToServerEncryptionKey = Uint8List.fromList(clientToServerEncryptionKey),
       serverToClientEncryptionKey = Uint8List.fromList(serverToClientEncryptionKey),
       clientToServerAuthenticationKey = Uint8List.fromList(clientToServerAuthenticationKey),
       serverToClientAuthenticationKey = Uint8List.fromList(serverToClientAuthenticationKey);

  final int clientToServerSpi;
  final int serverToClientSpi;
  final Uint8List clientToServerEncryptionKey;
  final Uint8List serverToClientEncryptionKey;
  final Uint8List clientToServerAuthenticationKey;
  final Uint8List serverToClientAuthenticationKey;

  @override
  String toString() => 'GlobalProtectIpsecKeyMaterial(<redacted>)';
}

class GlobalProtectTunnelConfig {
  const GlobalProtectTunnelConfig({
    this.ipAddress,
    this.ipv6Address,
    this.netmask,
    this.mtu,
    this.gatewayAddress,
    this.dnsServers = const [],
    this.dnsSuffixes = const [],
    this.includeRoutes = const [],
    this.excludeRoutes = const [],
    this.ipsec,
  });

  final String? ipAddress;
  final String? ipv6Address;
  final String? netmask;
  final int? mtu;
  final String? gatewayAddress;
  final List<String> dnsServers;
  final List<String> dnsSuffixes;
  final List<String> includeRoutes;
  final List<String> excludeRoutes;

  /// ESP/IPsec capability advertised by getconfig.esp.
  ///
  /// Sensitive ESP key material may also be retained in memory for the ESP data plane.
  final GlobalProtectIpsecConfig? ipsec;
}

class GlobalProtectConnection {
  const GlobalProtectConnection({
    required this.gateway,
    required this.session,
    required this.config,
    required this.transport,
  });

  final Uri gateway;
  final GlobalProtectSession session;
  final GlobalProtectTunnelConfig config;
  final GlobalProtectTransport transport;
}
