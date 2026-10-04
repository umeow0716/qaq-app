import 'package:flutter/material.dart';
import 'package:qaq_app/src/file/desktop_download_manager.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/util/file_utils.dart';

class DesktopDownloadPanel extends StatelessWidget {
  const DesktopDownloadPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = DesktopDownloadManager.instance;
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        if (!manager.panelVisible) return const SizedBox.shrink();
        final items = manager.items;

        return Material(
          elevation: 7,
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 360,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 310),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(R.current.download, style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                            onPressed: manager.clearPanel,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 14,
                        endIndent: 14,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                      itemBuilder: (context, index) => _DownloadItemTile(item: items[index]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DownloadItemTile extends StatelessWidget {
  const _DownloadItemTile({required this.item});

  final DesktopDownloadItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = item.progress;
    final failed = item.status == DesktopDownloadStatus.failed;
    final completed = item.status == DesktopDownloadStatus.completed;

    String status;
    if (failed) {
      status = R.current.downloadError;
    } else if (completed) {
      status = R.current.downloadComplete;
    } else if (item.status == DesktopDownloadStatus.preparing) {
      status = R.current.prepareDownload;
    } else if (item.totalBytes > 0) {
      final percent = ((progress ?? 0) * 100).round();
      status =
          '$percent% · ${FileUtils.formatBytes(item.receivedBytes, 2)} / '
          '${FileUtils.formatBytes(item.totalBytes, 2)}';
    } else {
      status = FileUtils.formatBytes(item.receivedBytes, 2);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: failed ? colorScheme.error : colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: completed ? 1 : progress,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: failed ? colorScheme.error : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
