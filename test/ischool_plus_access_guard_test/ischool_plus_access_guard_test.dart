import 'package:qaq_app/src/connector/ischool_plus_access_guard.dart';
import 'package:qaq_app/src/model/setting/setting_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VPN auto-connect setting defaults to disabled', () {
    expect(OtherSettingJson().autoConnectIStudyVpn, isFalse);
    expect(OtherSettingJson.fromJson(const <String, dynamic>{}).autoConnectIStudyVpn, isFalse);
  });

  test('reachable iStudy host always uses the direct route', () {
    expect(
      IStudyAccessGuard.routeFor(directReachable: true, autoConnectVpn: false),
      IStudyAccessRoute.direct,
    );
    expect(
      IStudyAccessGuard.routeFor(directReachable: true, autoConnectVpn: true),
      IStudyAccessRoute.direct,
    );
  });

  test('unreachable iStudy route is blocked while auto VPN is disabled', () {
    expect(
      IStudyAccessGuard.routeFor(directReachable: false, autoConnectVpn: false),
      IStudyAccessRoute.blocked,
    );
  });

  test('unreachable iStudy route uses VPN while auto VPN is enabled', () {
    expect(
      IStudyAccessGuard.routeFor(directReachable: false, autoConnectVpn: true),
      IStudyAccessRoute.vpn,
    );
  });

  test('only guards the iStudy host', () {
    expect(IStudyAccessGuard.isIStudyUri(Uri.parse('https://istudy.ntut.edu.tw/mooc/')), isTrue);
    expect(IStudyAccessGuard.isIStudyUri(Uri.parse('https://nportal.ntut.edu.tw/')), isFalse);
  });
}
