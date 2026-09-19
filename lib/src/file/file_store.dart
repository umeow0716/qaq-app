import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileStore {
  static const storeKey = "downloadPath";

  static Future<String> findLocalPath() async {
    final filePath = await _getFilePath();
    final directory = filePath != null || Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationSupportDirectory();

    final targetDir = Directory('${directory?.path ?? ''}/TAT');
    final hasExisted = await targetDir.exists();
    if (!hasExisted) {
      targetDir.create();
    }

    return targetDir.path;
  }

  static Future<String> getDownloadDir(String name) async {
    final localPath = '${await findLocalPath()}/$name';
    final savedDir = Directory(localPath);
    final hasExisted = await savedDir.exists();

    if (!hasExisted) {
      savedDir.create();
    }

    return savedDir.path;
  }

  static Future<Directory?> _getFilePath() async {
    final pref = await SharedPreferences.getInstance();
    final path = pref.getString(storeKey);
    if (path != null && path.isNotEmpty) {
      return Directory(base64Decode(path).toString());
    }

    return null;
  }
}
