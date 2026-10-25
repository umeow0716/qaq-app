import 'dart:io';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:qaq_app/src/config/app_config.dart';

class FileActionUtil {
  FileActionUtil._();

  static const MethodChannel _platform = MethodChannel(AppConfig.methodChannelName);

  static Future<String?> saveAs(String filePath) async {
    final file = File(filePath);
    final basename = path.basename(file.path);
    final extension = path.extension(basename).replaceFirst('.', '');
    final name = extension.isEmpty ? basename : path.basenameWithoutExtension(basename);
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

    return FileSaver.instance.saveAs(
      name: name,
      filePath: file.path,
      fileExtension: extension,
      mimeType: MimeType.custom,
      customMimeType: mimeType,
    );
  }

  static Future<void> shareFile(String filePath, {String? mimeType}) async {
    final file = File(filePath);
    if (!await file.exists()) throw FileSystemException('File does not exist', filePath);
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('System file sharing is only supported on Android and iOS.');
    }

    final shared = await _platform.invokeMethod<bool>('share_file', <String, Object?>{
      'path': file.path,
      'mimeType': mimeType ?? lookupMimeType(file.path) ?? 'application/octet-stream',
    });
    if (shared != true) throw StateError('Unable to open the system share sheet.');
  }
}
