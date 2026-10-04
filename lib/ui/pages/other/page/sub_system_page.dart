import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/model/ntut/ap_tree_json.dart';
import 'package:qaq_app/src/task/ntut/ntut_sub_system_task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/ui/other/route_utils.dart';

typedef SubSystemLinkOpenCallback = FutureOr<void> Function(Uri url, String title);

class SubSystemPage extends StatefulWidget {
  final String title;
  final String? arg;
  final bool embedded;
  final SubSystemLinkOpenCallback? onLinkOpen;

  const SubSystemPage({
    super.key,
    required this.title,
    this.arg,
    this.embedded = false,
    this.onLinkOpen,
  });

  @override
  State<SubSystemPage> createState() => _SubSystemPageState();
}

class _SubSystemPageState extends State<SubSystemPage> {
  bool isLoading = true;
  APTreeJson? apTree;
  late String _currentTitle;
  String? _currentArg;
  final List<_SubSystemLocation> _history = <_SubSystemLocation>[];

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title;
    _currentArg = widget.arg;
    loadTree(_currentArg);
  }

  Future<void> loadTree(String? arg) async {
    if (mounted) {
      setState(() => isLoading = true);
    }
    final taskFlow = TaskFlow();
    final task = NTUTSubSystemTask(arg)..openLoadingDialog = !widget.embedded;
    taskFlow.addTask(task);
    try {
      if (await taskFlow.start()) {
        apTree = task.result;
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _openFolder(APListJson ap) async {
    if (!widget.embedded) {
      await RouteUtils.toSubSystemPage(ap.description, ap.apDn);
      return;
    }

    _history.add(_SubSystemLocation(_currentTitle, _currentArg));
    _currentTitle = ap.description;
    _currentArg = ap.apDn;
    await loadTree(_currentArg);
  }

  Future<void> _goBackEmbedded() async {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    _currentTitle = previous.title;
    _currentArg = previous.arg;
    await loadTree(_currentArg);
  }

  Future<void> _openLink(APListJson ap) async {
    Uri? target;
    final apLinkUrl = Uri.tryParse(ap.urlLink);
    if (apLinkUrl != null && apLinkUrl.hasScheme) {
      target = apLinkUrl;
    } else {
      target = Uri.tryParse('${NTUTConnector.host}${ap.urlLink}');
    }
    if (target == null) return;

    final callback = widget.onLinkOpen;
    if (callback != null) {
      await callback(target, ap.description);
      return;
    }

    await RouteUtils.toWebViewPage(
      initialUrl: target,
      title: ap.description,
      shouldUseAppCookies: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = isLoading && !widget.embedded ? const Center(child: CircularProgressIndicator()) : _buildTree();

    if (!widget.embedded) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: body);
    }

    return Column(
      children: [
        SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (_history.isNotEmpty)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => unawaited(_goBackEmbedded()),
                    icon: const Icon(Icons.arrow_back),
                  )
                else
                  const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45)),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: IgnorePointer(ignoring: isLoading, child: body)),
              if (isLoading)
                const Center(child: _EmbeddedSubSystemLoadingBadge()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTree() {
    final tree = apTree;
    if (tree == null) return const SizedBox.shrink();

    if (!widget.embedded) {
      return ListView.builder(
        shrinkWrap: true,
        itemCount: tree.apList.length,
        itemBuilder: (BuildContext context, int index) {
          final ap = tree.apList[index];
          return InkWell(
            onTap: () => unawaited(ap.type == 'link' ? _openLink(ap) : _openFolder(ap)),
            child: SizedBox(
              height: 50,
              child: Row(
                children: [
                  Expanded(flex: 1, child: Icon((ap.type == 'link') ? Icons.link_outlined : Icons.folder_outlined)),
                  Expanded(flex: 8, child: Text(ap.description)),
                ],
              ),
            ),
          );
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: tree.apList.length,
      separatorBuilder: (context, index) => const SizedBox(height: 2),
      itemBuilder: (BuildContext context, int index) {
        final ap = tree.apList[index];
        final isLink = ap.type == 'link';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => unawaited(isLink ? _openLink(ap) : _openFolder(ap)),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Icon(isLink ? Icons.link_outlined : Icons.folder_outlined),
                  ),
                  Expanded(
                    child: Text(
                      ap.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    isLink ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
                    size: 19,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

}

class _EmbeddedSubSystemLoadingBadge extends StatelessWidget {
  const _EmbeddedSubSystemLoadingBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: const SizedBox(
        width: 52,
        height: 52,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: RepaintBoundary(
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      ),
    );
  }
}

class _SubSystemLocation {
  const _SubSystemLocation(this.title, this.arg);

  final String title;
  final String? arg;
}
