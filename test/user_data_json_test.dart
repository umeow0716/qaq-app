import 'package:flutter_test/flutter_test.dart';
import 'package:qaq_app/src/model/userdata/user_data_json.dart';

void main() {
  test('password is never serialized back to user data JSON', () {
    final user = UserDataJson(account: '123456789', password: 'super-secret');

    final json = user.toJson();

    expect(json['account'], '123456789');
    expect(json.containsKey('password'), isFalse);
  });

  test('legacy plaintext password can still be read for migration', () {
    final user = UserDataJson.fromJson(<String, dynamic>{
      'account': '123456789',
      'password': 'legacy-secret',
      'info': <String, dynamic>{},
    });

    expect(user.password, 'legacy-secret');
  });

  test('toString reports credential presence without exposing values', () {
    final user = UserDataJson(
      account: '123456789',
      password: 'super-secret',
      info: UserInfoJson(givenName: 'Private Name', userMail: 'private@example.com'),
    );

    final text = user.toString();

    expect(text, contains('accountPresent: true'));
    expect(text, contains('passwordPresent: true'));
    expect(text, isNot(contains('123456789')));
    expect(text, isNot(contains('super-secret')));
    expect(text, isNot(contains('Private Name')));
    expect(text, isNot(contains('private@example.com')));
  });
}
