import 'dart:io';

import 'package:flutter/material.dart';
import "package:lucide_icons_flutter/lucide_icons.dart";
import 'package:mime/mime.dart';
import 'package:path/path.dart';

class FileIcon extends StatelessWidget {
  final FileSystemEntity file;

  const FileIcon({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    final f = File(file.path);
    final configuredExtension = extension(f.path).toLowerCase();
    final mimeType = lookupMimeType(basename(file.path).toLowerCase());
    final type = mimeType == null ? "" : mimeType.split("/")[0];
    if (configuredExtension == ".apk") {
      return const Icon(Icons.android, color: Colors.green);
    } else if (configuredExtension == ".crdownload") {
      return const Icon(LucideIcons.download, color: Colors.lightBlue);
    } else if (configuredExtension == ".zip" || configuredExtension.contains("tar")) {
      return const Icon(LucideIcons.archive);
    } else if (configuredExtension == ".epub" || configuredExtension == ".pdf" || configuredExtension == ".mobi") {
      return const Icon(LucideIcons.fileText, color: Colors.orangeAccent);
    } else {
      switch (type) {
        case "image":
          {
            return Image.file(f, height: 40, width: 40);
          }
        case "audio":
          {
            return const Icon(LucideIcons.music, color: Colors.blue);
          }

        case "text":
          {
            return const Icon(LucideIcons.fileText, color: Colors.orangeAccent);
          }

        default:
          {
            return const Icon(LucideIcons.file);
          }
      }
    }
  }
}
