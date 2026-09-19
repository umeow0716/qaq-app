import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/model/setting/setting_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VPN auto-connect setting defaults to disabled', () {
    expect(OtherSettingJson().autoConnectIStudyVpn, isFalse);
    expect(OtherSettingJson.fromJson(const <String, dynamic>{}).autoConnectIStudyVpn, isFalse);
  });

  test('classifies 140.* public IPv4 as campus network', () {
    expect(CampusNetworkDetector.classifyPublicIp('140.124.13.1'), CampusNetworkStatus.onCampus);
  });

  test('classifies non-140 IPv4 as off-campus network', () {
    expect(CampusNetworkDetector.classifyPublicIp('8.8.8.8'), CampusNetworkStatus.offCampus);
  });

  test('unknown public IP does not pretend to be off-campus', () {
    expect(CampusNetworkDetector.classifyPublicIp(null), CampusNetworkStatus.unknown);
    expect(CampusNetworkDetector.classifyPublicIp('not-an-ip'), CampusNetworkStatus.unknown);
  });

  test('off-campus route is blocked while auto VPN is disabled', () {
    expect(IStudyAccessGuard.routeFor(CampusNetworkStatus.offCampus, autoConnectVpn: false), IStudyAccessRoute.blocked);
  });

  test('off-campus route uses VPN while auto VPN is enabled', () {
    expect(IStudyAccessGuard.routeFor(CampusNetworkStatus.offCampus, autoConnectVpn: true), IStudyAccessRoute.vpn);
  });

  test('campus and unknown states keep the direct route', () {
    expect(IStudyAccessGuard.routeFor(CampusNetworkStatus.onCampus, autoConnectVpn: true), IStudyAccessRoute.direct);
    expect(IStudyAccessGuard.routeFor(CampusNetworkStatus.unknown, autoConnectVpn: true), IStudyAccessRoute.direct);
  });

  test('only guards the iStudy host', () {
    expect(IStudyAccessGuard.isIStudyUri(Uri.parse('https://istudy.ntut.edu.tw/mooc/')), isTrue);
    expect(IStudyAccessGuard.isIStudyUri(Uri.parse('https://nportal.ntut.edu.tw/')), isFalse);
  });
}
