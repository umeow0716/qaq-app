import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qaq_app/src/config/app_themes.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_app_session.dart';
import 'package:qaq_app/src/connector/global_protect/global_protect_webview_runtime.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/portal/desktop_portal_shortcuts.dart';
import 'package:qaq_app/src/providers/app_provider.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/task/ntut/ntut_task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/src/util/language_util.dart';
import 'package:qaq_app/ui/desktop/desktop_download_panel.dart';
import 'package:qaq_app/ui/other/my_toast.dart';
import 'package:qaq_app/ui/other/route_utils.dart';
import 'package:qaq_app/ui/pages/other/page/sub_system_page.dart';
import 'package:qaq_app/ui/pages/calendar/calendar_page.dart';
import 'package:qaq_app/ui/pages/coursedetail/desktop_course_inspector.dart';
import 'package:qaq_app/ui/pages/coursetable/course_table_page.dart';
import 'package:qaq_app/ui/pages/score/score_page.dart';
import 'package:qaq_app/ui/pages/webview/qaq_web_view.dart';
import 'package:provider/provider.dart';

class DesktopMainScreen extends StatefulWidget {
  const DesktopMainScreen({super.key});

  @override
  State<DesktopMainScreen> createState() => _DesktopMainScreenState();
}

class _DesktopMainScreenState extends State<DesktopMainScreen> with SingleTickerProviderStateMixin {
  static const double _workspaceTabHeight = 44.0;
  static const double _profileTop = 24.0;
  static const double _profileAvatarSize = 52.0;
  static const double _profileToWorkspaceFrameGap = 16.0;
  static const double _workspaceFrameTop = _profileTop + _profileAvatarSize + _profileToWorkspaceFrameGap;
  static const double _workspaceTop = _workspaceFrameTop - _workspaceTabHeight + 1;
  static const double _workspaceBottomClearance = 42.0;

  int _workspaceIndex = 0;
  CourseInfoJson? _selectedCourse;
  late final AnimationController _courseInspectorController;
  bool _courseTableCompactLayout = false;
  bool _courseInspectorTransitioning = false;
  Future<Uint8List?>? _avatarFuture;
  Uint8List? _lastAvatarBytes;
  bool _avatarUploading = false;
  Uri? _focusWebViewUri;
  String? _focusWebViewTitle;

  bool get _isEnglish => LanguageUtil.getLangIndex() == LangEnum.en;
  String get _courseSystemLabel => _isEnglish ? 'Course system' : '課程系統';
  String get _vpnLabel => 'VPN';
  String get _chooseAvatarLabel => _isEnglish ? 'Choose from files' : '從檔案選擇';

  @override
  void initState() {
    super.initState();
    _courseInspectorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _avatarFuture = _loadAvatar();
  }

  @override
  void dispose() {
    _courseInspectorController.dispose();
    super.dispose();
  }

  Future<void> _openPortalShortcut(DesktopPortalShortcut shortcut) async {
    await _openCourseSystemLink(shortcut.uri, shortcut.label(english: _isEnglish));
  }

  Future<Uint8List?> _loadAvatar() async {
    try {
      final taskFlow = TaskFlow();
      final task = NTUTTask('DesktopAvatar')..openLoadingDialog = false;
      taskFlow.addTask(task);
      if (!await taskFlow.start()) return _lastAvatarBytes;
      final bytes = await NTUTConnector.getUserImageBytes();
      _lastAvatarBytes = bytes;
      return bytes;
    } catch (_) {
      return _lastAvatarBytes;
    }
  }

  Future<void> _pickAvatarFromFile() async {
    if (_avatarUploading) return;
    final image = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Images', extensions: <String>['png', 'jpg', 'jpeg', 'webp']),
      ],
    );
    if (image == null) return;

    setState(() => _avatarUploading = true);
    try {
      final imageBytes = await image.readAsBytes();
      final taskFlow = TaskFlow();
      final loginTask = NTUTTask('DesktopAvatarUpload')..openLoadingDialog = false;
      taskFlow.addTask(loginTask);
      if (!await taskFlow.start()) return;

      final newFilename = await NTUTConnector.uploadUserImage(imageBytes);
      LocalStorage.instance.getUserInfo().userPhoto = newFilename;
      await LocalStorage.instance.saveUserData();
      await LocalStorage.instance.cacheManager.emptyCache();
      if (!mounted) return;
      setState(() {
        _lastAvatarBytes = imageBytes;
        _avatarFuture = Future<Uint8List?>.value(imageBytes);
      });
      MyToast.show(R.current.avatarUpdated);
    } catch (_) {
      MyToast.show(R.current.avatarUpdateFailed);
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(R.current.warning),
        content: Text(R.current.logoutWarning),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(R.current.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(R.current.sure)),
        ],
      ),
    );
    if (confirmed != true) return;
    TaskFlow.resetLoginStatus();
    await LocalStorage.instance.logout();
    await RouteUtils.toLoginScreen();
  }

  void _selectWorkspace(int index) {
    if (index == _workspaceIndex) return;
    if (index != 0 && _selectedCourse != null) {
      _courseInspectorController.value = 0;
    }
    setState(() {
      _workspaceIndex = index;
      if (index != 0) {
        _selectedCourse = null;
        _courseTableCompactLayout = false;
        _courseInspectorTransitioning = false;
      }
    });
  }

  Future<void> _openCourseSystemLink(Uri uri, String title) async {
    setState(() {
      _focusWebViewUri = uri;
      _focusWebViewTitle = title;
    });
  }

  void _closeFocusWebView() {
    setState(() {
      _focusWebViewUri = null;
      _focusWebViewTitle = null;
    });
  }

  void _selectCourse(CourseInfoJson course) {
    if (_courseInspectorTransitioning) return;

    final selected = _selectedCourse;
    final sameId =
        selected != null && selected.main.course.id.isNotEmpty && selected.main.course.id == course.main.course.id;
    final sameFallback =
        selected != null && selected.main.course.id.isEmpty && selected.main.course.name == course.main.course.name;

    if (sameId || sameFallback) {
      unawaited(_closeCourseInspector());
      return;
    }

    if (selected != null && _courseTableCompactLayout) {
      setState(() => _selectedCourse = course);
      return;
    }

    _courseInspectorController.value = 0;
    setState(() {
      _selectedCourse = course;
      _courseInspectorTransitioning = true;
      // Keep the full-width timetable layout during the transition. Its
      // RepaintBoundary is compressed by a compositor transform, so the
      // dozens of timetable cells never relayout frame-by-frame.
      _courseTableCompactLayout = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedCourse == null) return;
      unawaited(_openCourseInspector());
    });
  }

  Future<void> _openCourseInspector() async {
    try {
      await _courseInspectorController.forward(from: 0).orCancel;
      if (!mounted || _selectedCourse == null) return;

      // Commit the final two-column layout only after the paint-only
      // transition is complete. The visual width is unchanged at this point,
      // so this single relayout is not visible as a jump.
      setState(() {
        _courseTableCompactLayout = true;
        _courseInspectorTransitioning = false;
      });
    } on TickerCanceled {
      // The screen was disposed while the transition was running.
    }
  }

  Future<void> _closeCourseInspector() async {
    if (_selectedCourse == null || _courseInspectorTransitioning) return;
    setState(() => _courseInspectorTransitioning = true);

    try {
      await _courseInspectorController.reverse(from: 1).orCancel;
      if (!mounted) return;

      // The compact timetable has been paint-expanded back to the full
      // workspace width. Commit the full-width constraints once, after the
      // animation, then remove the inspector.
      setState(() {
        _selectedCourse = null;
        _courseTableCompactLayout = false;
        _courseInspectorTransitioning = false;
      });
    } on TickerCanceled {
      // The screen was disposed while the transition was running.
    }
  }

  Future<void> _toggleVpn(bool enabled) async {
    final setting = LocalStorage.instance.getOtherSetting();
    setting.autoConnectIStudyVpn = enabled;
    await LocalStorage.instance.saveOtherSetting();
    if (!enabled) {
      unawaited(GlobalProtectWebViewRuntime.reset());
      unawaited(GlobalProtectAppSession.instance.disconnect());
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_focusWebViewUri != null) {
            _closeFocusWebView();
          } else if (_selectedCourse != null) {
            unawaited(_closeCourseInspector());
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalMargin = constraints.maxWidth >= 1200 ? 48.0 : 28.0;
                const workspaceFrameTop = _workspaceFrameTop;
                final rawWorkspaceWidth = constraints.maxWidth - horizontalMargin * 2;
                final showPortalRail = constraints.maxWidth >= 1000;
                final portalRailWidth = constraints.maxWidth >= 1240 ? 226.0 : 198.0;
                const portalRailGap = 22.0;
                final maxWorkspaceWidth = rawWorkspaceWidth - (showPortalRail ? portalRailWidth + portalRailGap : 0);
                // Keep the desktop workspace geometry stable while contextual UI
                // opens. Resizing the whole IndexedStack here forces hidden pages
                // (notably TableCalendar's internal AnimatedSize) to relayout in
                // the middle of their own animation/layout pass.
                const preferredWidth = 1120.0;
                final desiredWidth = showPortalRail
                    ? (preferredWidth < maxWorkspaceWidth ? preferredWidth : maxWorkspaceWidth)
                    : (preferredWidth < rawWorkspaceWidth * 0.80 ? preferredWidth : rawWorkspaceWidth * 0.80);
                final workspaceWidth =
                    (maxWorkspaceWidth < 680.0 ? maxWorkspaceWidth : desiredWidth.clamp(680.0, maxWorkspaceWidth))
                        .toDouble();
                final availableWorkspaceHeight = constraints.maxHeight - _workspaceTop - _workspaceBottomClearance;
                final workspaceHeight = availableWorkspaceHeight.clamp(520.0, 780.0).toDouble();

                return Stack(
                  children: [
                    Positioned(top: _profileTop, right: horizontalMargin, child: _buildProfile()),
                    Positioned(
                      left: horizontalMargin,
                      top: _workspaceTop,
                      width: workspaceWidth,
                      height: workspaceHeight,
                      child: _buildWorkspace(colorScheme),
                    ),
                    if (showPortalRail)
                      Positioned(
                        top: workspaceFrameTop,
                        right: horizontalMargin,
                        bottom: _workspaceBottomClearance,
                        width: portalRailWidth,
                        child: _buildPortalShortcutRail(),
                      ),
                    Positioned(right: horizontalMargin, bottom: 18, child: _buildUtilityDock(appProvider)),
                    if (_focusWebViewUri != null) Positioned.fill(child: _buildWebViewFocusMode(colorScheme)),
                    Positioned(right: horizontalMargin, bottom: 72, child: const DesktopDownloadPanel()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebViewFocusMode(ColorScheme colorScheme) {
    final target = _focusWebViewUri;
    if (target == null) return const SizedBox.shrink();
    final title = (_focusWebViewTitle ?? '').trim();

    return ColoredBox(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
          ),
          child: _buildFocusWebView(target, title),
        ),
      ),
    );
  }

  Widget _buildFocusWebView(Uri target, String title) {
    final webView = QAQWebView(
      initialUrl: target,
      title: title.isEmpty ? _courseSystemLabel : title,
      showAppBar: true,
      onDesktopClose: _closeFocusWebView,
    );

    if (Platform.isLinux) {
      // webview_all_linux hosts WebKitGTK as a native GTK overlay. A rounded
      // Flutter clip cannot be represented by that overlay, so the plugin
      // deliberately hides the native WebView instead of rendering it outside
      // the clip. Keep the Linux WebView rectangular; Windows keeps the
      // existing rounded ClipRRect path unchanged.
      return webView;
    }

    return ClipRRect(borderRadius: BorderRadius.circular(22), child: webView);
  }

  Widget _buildWorkspace(ColorScheme colorScheme) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: _workspaceTabHeight - 1,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: IndexedStack(
                index: _workspaceIndex,
                children: [
                  TickerMode(enabled: _workspaceIndex == 0, child: _buildCourseWorkspace()),
                  TickerMode(enabled: _workspaceIndex == 1, child: const CalendarPage()),
                  TickerMode(enabled: _workspaceIndex == 2, child: const ScoreViewerPage()),
                  TickerMode(
                    enabled: _workspaceIndex == 3,
                    child: SubSystemPage(
                      title: R.current.informationSystem,
                      embedded: true,
                      onLinkOpen: _openCourseSystemLink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          top: 0,
          height: _workspaceTabHeight,
          child: Row(
            children: [
              _WorkspaceTab(
                label: R.current.titleCourse,
                selected: _workspaceIndex == 0,
                onTap: () => _selectWorkspace(0),
              ),
              _WorkspaceTab(
                label: R.current.calendar,
                selected: _workspaceIndex == 1,
                onTap: () => _selectWorkspace(1),
              ),
              _WorkspaceTab(
                label: R.current.titleScore,
                selected: _workspaceIndex == 2,
                onTap: () => _selectWorkspace(2),
              ),
              _WorkspaceTab(
                label: _courseSystemLabel,
                selected: _workspaceIndex == 3,
                onTap: () => _selectWorkspace(3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCourseWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        final inspectorWidth = (fullWidth * 0.34).clamp(280.0, 390.0).toDouble();
        final compactWidth = (fullWidth - inspectorWidth).clamp(420.0, fullWidth).toDouble();
        final hasInspector = _selectedCourse != null;
        final layoutCompact = hasInspector && _courseTableCompactLayout;
        final layoutWidth = layoutCompact ? compactWidth : fullWidth;

        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: layoutWidth,
              child: IgnorePointer(
                ignoring: _courseInspectorTransitioning,
                child: AnimatedBuilder(
                  animation: _courseInspectorController,
                  child: RepaintBoundary(
                    child: CourseTablePage(
                      onCourseSelected: _selectCourse,
                      onBeforeSemesterChange: _closeCourseInspector,
                    ),
                  ),
                  builder: (context, child) {
                    final progress = Curves.easeInOutCubic.transform(_courseInspectorController.value);
                    double scaleX = 1;

                    if (hasInspector && _courseInspectorTransitioning) {
                      if (layoutCompact) {
                        // Closing: the compact final layout is paint-expanded
                        // back to the full workspace before the one final
                        // constraint rebuild.
                        final fullScale = fullWidth / compactWidth;
                        scaleX = fullScale - ((fullScale - 1) * progress);
                      } else {
                        // Opening: keep the full-width layout and compress the
                        // entire layer toward its final compact width.
                        final compactScale = compactWidth / fullWidth;
                        scaleX = 1 - ((1 - compactScale) * progress);
                      }
                    }

                    return Transform(
                      alignment: Alignment.centerLeft,
                      transform: Matrix4.diagonal3Values(scaleX, 1, 1),
                      child: child,
                    );
                  },
                ),
              ),
            ),
            if (hasInspector)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: inspectorWidth,
                child: IgnorePointer(
                  ignoring: _courseInspectorTransitioning,
                  child: AnimatedBuilder(
                    animation: _courseInspectorController,
                    child: RepaintBoundary(
                      child: DesktopCourseInspector(
                        key: ValueKey(
                          'course-inspector-${_selectedCourse!.main.course.id}-${_selectedCourse!.main.course.name}',
                        ),
                        studentId: LocalStorage.instance.getCourseSetting().info.studentId,
                        courseInfo: _selectedCourse!,
                        onClose: () => unawaited(_closeCourseInspector()),
                      ),
                    ),
                    builder: (context, child) {
                      final progress = Curves.easeInOutCubic.transform(_courseInspectorController.value);
                      return Opacity(
                        opacity: progress,
                        child: Transform.translate(offset: Offset(inspectorWidth * (1 - progress), 0), child: child),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildProfile() {
    final userInfo = LocalStorage.instance.getUserInfo();
    final name = userInfo.givenName.trim();
    final email = userInfo.userMail.trim();
    final hasAccount = LocalStorage.instance.getAccount().isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name.isNotEmpty || email.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (name.isNotEmpty) Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (email.isNotEmpty)
                  Text(email, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        PopupMenuButton<_ProfileAction>(
          tooltip: '',
          offset: const Offset(0, 52),
          onSelected: (action) {
            switch (action) {
              case _ProfileAction.avatar:
                unawaited(_pickAvatarFromFile());
                break;
              case _ProfileAction.login:
                unawaited(RouteUtils.toLoginScreen());
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ProfileAction.avatar,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image_outlined),
                title: Text(_chooseAvatarLabel),
              ),
            ),
            if (!hasAccount)
              PopupMenuItem(
                value: _ProfileAction.login,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.login),
                  title: Text(R.current.login),
                ),
              ),
          ],
          child: SizedBox(
            width: _profileAvatarSize,
            height: _profileAvatarSize,
            child: _avatarUploading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: RepaintBoundary(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : FutureBuilder<Uint8List?>(
                    future: _avatarFuture,
                    builder: (context, snapshot) {
                      final bytes = snapshot.data ?? _lastAvatarBytes;
                      return CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        backgroundImage: bytes == null ? null : MemoryImage(bytes),
                        child: bytes == null ? const Icon(Icons.person_outline) : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortalShortcutRail() {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final shortcut in desktopPortalShortcuts)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => unawaited(_openPortalShortcut(shortcut)),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      backgroundColor: colorScheme.surfaceContainerLow.withValues(alpha: 0.72),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: Text(
                      shortcut.label(english: _isEnglish),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUtilityDock(AppProvider appProvider) {
    final vpnEnabled = LocalStorage.instance.getOtherSetting().autoConnectIStudyVpn;
    final dark = appProvider.isDarkTheme;
    final english = _isEnglish;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _UtilityPill(
              icon: Icons.shield_outlined,
              label: '$_vpnLabel ${vpnEnabled ? 'On' : 'Off'}',
              active: vpnEnabled,
              tooltip: R.current.autoConnectIStudyVpn,
              onTap: () => _toggleVpn(!vpnEnabled),
            ),
            _UtilityPill(
              icon: dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              label: dark ? 'Dark' : 'Light',
              active: dark,
              tooltip: _isEnglish ? 'Theme' : '主題',
              onTap: () {
                if (dark) {
                  appProvider.setTheme(AppThemes.lightTheme, 'light');
                } else {
                  appProvider.setTheme(AppThemes.darkTheme, 'dark');
                }
              },
            ),
            _UtilityPill(
              icon: Icons.translate,
              label: english ? 'EN' : '中',
              active: english,
              tooltip: _isEnglish ? 'Language' : '語言',
              onTap: () => LanguageUtil.setLangByIndex(english ? LangEnum.zh : LangEnum.en),
            ),
            if (LocalStorage.instance.getAccount().isNotEmpty)
              _UtilityPill(
                icon: Icons.logout,
                label: R.current.logout,
                active: false,
                tooltip: R.current.logout,
                onTap: () => unawaited(_logout()),
              ),
            IconButton(
              tooltip: R.current.PrivacyPolicy,
              onPressed: RouteUtils.toPrivacyPolicyPage,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ProfileAction { avatar, login }

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.65);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: onTap,
            child: Container(
              alignment: Alignment.center,
              decoration: selected
                  ? BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      border: Border(
                        left: BorderSide(color: borderColor),
                        top: BorderSide(color: borderColor),
                        right: BorderSide(color: borderColor),
                      ),
                    )
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UtilityPill extends StatelessWidget {
  const _UtilityPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final child = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: active ? colorScheme.primary : colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}
