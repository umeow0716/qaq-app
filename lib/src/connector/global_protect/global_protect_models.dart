import 'dart:collection';

import 'global_protect_tunnel.dart';

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
  GlobalProtectSession({
    required Map<String, String> values,
  }) : values = UnmodifiableMapView(Map<String, String>.from(values));

  final Map<String, String> values;

  String get user => values['user'] ?? '';
  String get authCookie => values['authcookie'] ?? '';

  Map<String, String> get tunnelQuery {
    final result = <String, String>{};
    final user = values['user'];
    final authCookie = values['authcookie'];
    if (user != null && user.isNotEmpty) result['user'] = user;
    if (authCookie != null && authCookie.isNotEmpty) result['authcookie'] = authCookie;
    return result;
  }
}

class GlobalProtectTunnelConfig {
  const GlobalProtectTunnelConfig({
    required this.tunnelPath,
    this.ipAddress,
    this.ipv6Address,
    this.netmask,
    this.mtu,
    this.gatewayAddress,
    this.dnsServers = const [],
    this.dnsSuffixes = const [],
    this.includeRoutes = const [],
    this.excludeRoutes = const [],
  });

  final String tunnelPath;
  final String? ipAddress;
  final String? ipv6Address;
  final String? netmask;
  final int? mtu;
  final String? gatewayAddress;
  final List<String> dnsServers;
  final List<String> dnsSuffixes;
  final List<String> includeRoutes;
  final List<String> excludeRoutes;
}

class GlobalProtectConnection {
  const GlobalProtectConnection({
    required this.gateway,
    required this.session,
    required this.config,
    required this.tunnel,
  });

  final Uri gateway;
  final GlobalProtectSession session;
  final GlobalProtectTunnelConfig config;
  final GlobalProtectTunnel tunnel;
}
