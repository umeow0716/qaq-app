import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qaq_app/src/connector/core/network_request_pool.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/share/course_table_share_codec.dart';
import 'package:qaq_app/src/share/course_table_share_data.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/sync/course_table_cloud_sync.dart';
import 'package:qaq_app/src/task/course/course_semester_task.dart';
import 'package:qaq_app/src/task/course/course_table_task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/src/util/file_action_util.dart';
import 'package:qaq_app/ui/other/msg_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';

class CourseTableSharePage extends StatefulWidget {
  const CourseTableSharePage({super.key});

  @override
  State<CourseTableSharePage> createState() => _CourseTableSharePageState();
}

class _CourseTableSharePageState extends State<CourseTableSharePage> {
  MobileScannerController? _scannerController;

  late final String _account;
  List<CourseTableJson> _courseTables = <CourseTableJson>[];
  List<String> _semesterKeys = <String>[];
  final Set<String> _selectedSemesterKeys = <String>{};

  bool _loading = true;
  bool _scanning = false;
  bool _scanHandled = false;
  bool _exporting = false;
  bool _sharing = false;
  bool _importing = false;

  bool get _isDesktop => Platform.isWindows || Platform.isLinux;
  bool get _canScan => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_canScan) {
      _scannerController = MobileScannerController(
        autoStart: false,
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
    _account = LocalStorage.instance.getAccount().trim();
    unawaited(_loadAllCourseTables());
  }

  Future<void> _loadAllCourseTables() async {
    final storage = LocalStorage.instance;
    final semesterTask = CourseSemesterTask(_account)
      ..openLoadingDialog = false
      ..openErrorDialog = false;
    final semesterFlow = TaskFlow()..addTask(semesterTask);

    var semesterLoadSucceeded = false;
    try {
      semesterLoadSucceeded = await semesterFlow.start();
    } catch (_) {
      semesterLoadSucceeded = false;
    }

    final semesters = semesterTask.result;
    if (semesterLoadSucceeded && semesters != null) {
      storage.setSemesterJsonList(semesters);

      final missingSemesters = <SemesterJson>[];
      for (final semester in semesters) {
        final table = storage.getCourseTable(_account, semester);
        if (table == null || !table.getCourseIdList().any((id) => id.trim().isNotEmpty)) {
          missingSemesters.add(semester);
        }
      }

      var failedToLoadCourseTable = false;
      if (missingSemesters.isNotEmpty) {
        final loaded = await NetworkRequestPool.shared.run<CourseTableJson>(
          missingSemesters.map(
            (semester) =>
                (timeout) => CourseTableTask(_account, semester).loadAfterLogin(timeout: timeout, persist: false),
          ),
          shouldRetry: (table) => table == null || !table.getCourseIdList().any((id) => id.trim().isNotEmpty),
        );

        var savedAny = false;
        for (final table in loaded) {
          if (table == null || !table.getCourseIdList().any((id) => id.trim().isNotEmpty)) {
            failedToLoadCourseTable = true;
            continue;
          }
          storage.addCourseTable(table);
          savedAny = true;
        }
        if (savedAny) {
          await Future.wait([storage.saveCourseTableList(), storage.saveCourseExtraInfoCache()]);
        }
      }

      if (failedToLoadCourseTable && mounted) {
        _showInfo(R.current.getCourseError, type: DialogType.error);
      }
    } else if (mounted) {
      _showInfo(R.current.getCourseSemesterError, type: DialogType.error);
    }

    final loadedTables = storage
        .getCourseTableList()
        .where((table) => table.studentId.trim() == _account)
        .where((table) => table.getCourseIdList().any((id) => id.trim().isNotEmpty))
        .toList();

    final semesterKeys = <String>[];
    for (final table in loadedTables) {
      final key = CourseTableShareCodec.semesterKeyOf(table);
      if (key != '-' && !semesterKeys.contains(key)) semesterKeys.add(key);
    }
    semesterKeys.sort(_compareSemesterKeys);

    if (!mounted) return;
    setState(() {
      _courseTables = loadedTables;
      _semesterKeys = semesterKeys;
      _selectedSemesterKeys.clear();
      if (semesterKeys.isNotEmpty) _selectedSemesterKeys.add(semesterKeys.first);
      _loading = false;
    });
  }

  @override
  void dispose() {
    final scannerController = _scannerController;
    if (scannerController != null) unawaited(scannerController.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(R.current.courseShareTitle)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _semesterKeys.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(R.current.courseShareNoData, textAlign: TextAlign.center),
                ),
              )
            : _isDesktop
            ? _buildDesktop(context)
            : _buildMobile(context),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: _ShareCard(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildQrCode(maxSize: 310),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              R.current.courseShareSelectSemesters,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildSemesterSelector(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: _ShareCard(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _wideButton(
                                icon: Icons.file_open_outlined,
                                label: R.current.courseShareImportFile,
                                onPressed: _importing ? null : _importFile,
                              ),
                              const SizedBox(height: 14),
                              _wideButton(
                                icon: Icons.file_upload_outlined,
                                label: R.current.courseShareExportFile,
                                onPressed: _exporting ? null : _exportFile,
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Widget _buildMobile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: _ShareCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _scanning ? _buildScanner() : _buildQrCode(maxSize: 260),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: _buildSemesterSelector()),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _wideButton(
            icon: _scanning ? Icons.close : Icons.qr_code_scanner,
            label: _scanning ? R.current.cancel : R.current.courseShareScanQr,
            onPressed: _canScan ? _toggleScanner : null,
          ),
          const SizedBox(height: 10),
          _wideButton(
            icon: Icons.file_open_outlined,
            label: R.current.courseShareImportFile,
            onPressed: _importing ? null : _importFile,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _wideButton(
                  icon: Icons.file_upload_outlined,
                  label: R.current.courseShareExportFile,
                  onPressed: _exporting ? null : _exportFile,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _wideButton(
                  icon: Icons.share_outlined,
                  label: R.current.courseShareShareFile,
                  onPressed: _sharing ? null : _shareFile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrCode({required double maxSize}) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite ? constraints.maxWidth : maxSize;
        final size = available.clamp(180.0, maxSize).toDouble();
        return Container(
          key: const ValueKey<String>('course-share-qr'),
          width: size,
          height: size,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: QrImageView(
            data: _shareUrl,
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
            errorStateBuilder: (context, error) => Center(
              child: Icon(Icons.qr_code_2, size: size * 0.45, color: colorScheme.error),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanner() {
    return ConstrainedBox(
      key: const ValueKey<String>('course-share-scanner'),
      constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: MobileScanner(
            controller: _scannerController!,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Text(R.current.courseShareCameraUnavailable, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterSelector() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 132),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Align(
          alignment: Alignment.topCenter,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (final semester in _semesterKeys) _buildSemesterChip(semester)],
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterChip(String semester) {
    final selected = _selectedSemesterKeys.contains(semester);
    final checkColor = Theme.of(context).colorScheme.onSecondaryContainer;
    const checkSize = 18.0;
    const checkGap = 4.0;

    Widget checkedContent({required double opacity}) {
      return Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: checkSize, color: checkColor),
            const SizedBox(width: checkGap),
            Text(semester),
          ],
        ),
      );
    }

    return FilterChip(
      label: Stack(
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(child: checkedContent(opacity: 0)),
          if (selected) checkedContent(opacity: 1) else Text(semester),
        ],
      ),
      selected: selected,
      showCheckmark: false,
      onSelected: (value) => _setSemesterSelected(semester, value),
    );
  }

  Widget _wideButton({required IconData icon, required String label, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.tonalIcon(onPressed: onPressed, icon: Icon(icon), label: Text(label)),
    );
  }

  String get _shareUrl {
    final payload = CourseTableShareCodec.buildPayload(
      account: _account,
      courseTables: _courseTables,
      semesterKeys: _selectedSemesterKeys,
      fallbackName: LocalStorage.instance.getUserInfo().givenName,
    );
    return CourseTableShareCodec.encodeUrl(payload);
  }

  void _setSemesterSelected(String semester, bool selected) {
    if (!selected && _selectedSemesterKeys.length == 1 && _selectedSemesterKeys.contains(semester)) {
      _showInfo(R.current.courseShareKeepOneSemester);
      return;
    }
    setState(() {
      if (selected) {
        _selectedSemesterKeys.add(semester);
      } else {
        _selectedSemesterKeys.remove(semester);
      }
    });
  }

  void _toggleScanner() {
    if (_scanning) {
      unawaited(_scannerController!.stop());
      setState(() => _scanning = false);
      return;
    }

    _scanHandled = false;
    setState(() => _scanning = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scanning) return;
      unawaited(_startScanner());
    });
  }

  Future<void> _startScanner() async {
    try {
      await _scannerController!.start();
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _showInfo(R.current.courseShareCameraUnavailable, type: DialogType.error);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled) return;

    String? value;
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue != null && rawValue.isNotEmpty) {
        value = rawValue;
        break;
      }
    }
    if (value == null) return;

    _scanHandled = true;
    unawaited(_scannerController!.stop());
    if (mounted) setState(() => _scanning = false);
    unawaited(_importShareUrl(value));
  }

  Future<void> _importFile() async {
    if (_importing) return;
    try {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'QAQ Schedule', extensions: <String>[CourseTableShareCodec.fileExtension]),
        ],
      );
      if (file == null) return;

      final value = (await file.readAsString()).trim();
      await _importShareUrl(value);
    } catch (_) {
      _showInfo(R.current.courseShareImportFailed, type: DialogType.error);
    }
  }

  Future<void> _importShareUrl(String value) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final payload = CourseTableShareCodec.decodeUrl(value.trim());
      final people = CourseTableSharePerson.fromPayload(payload);
      if (people.isEmpty) throw const FormatException('No shared course tables');

      final account = LocalStorage.instance.getAccount().trim();
      if (people.any((person) => person.studentId.trim() == account)) {
        _showInfo(R.current.courseShareImportOwnAccount, type: DialogType.warning);
        return;
      }

      await LocalStorage.instance.importCourseTableSharePeople(people);
      unawaited(CourseTableCloudSync.instance.pushLocalSnapshot());
      _showInfo(R.current.courseShareImportSuccess, type: DialogType.success);
    } catch (_) {
      _showInfo(R.current.courseShareImportFailed, type: DialogType.error);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportFile() async {
    if (_selectedSemesterKeys.isEmpty || _exporting) return;
    setState(() => _exporting = true);

    try {
      final bytes = Uint8List.fromList(utf8.encode(_shareUrl));
      final result = await FileSaver.instance.saveAs(
        name: _exportFileName(),
        bytes: bytes,
        fileExtension: CourseTableShareCodec.fileExtension,
        mimeType: MimeType.custom,
        customMimeType: CourseTableShareCodec.mimeType,
      );
      if (result == null) return;
      _showInfo(R.current.courseShareExportedToFiles);
    } catch (_) {
      _showInfo(R.current.courseShareExportFailed, type: DialogType.error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareFile() async {
    if (_selectedSemesterKeys.isEmpty || _sharing) return;
    setState(() => _sharing = true);

    File? temporaryFile;
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      temporaryFile = File('${temporaryDirectory.path}/${_exportFileName()}.${CourseTableShareCodec.fileExtension}');
      await temporaryFile.writeAsString(_shareUrl, flush: true);
      await FileActionUtil.shareFile(temporaryFile.path, mimeType: CourseTableShareCodec.mimeType);
    } catch (_) {
      _showInfo(R.current.courseShareShareFailed, type: DialogType.error);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showInfo(String message, {DialogType type = DialogType.info}) {
    unawaited(
      MsgDialog(
        MsgDialogParameter(
          title: R.current.courseShareTitle,
          desc: message,
          dialogType: type,
          removeCancelButton: true,
        ),
      ).show(context: context),
    );
  }

  String _exportFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final timestamp =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'QAQ-course-table-$_account-$timestamp';
  }

  static int _compareSemesterKeys(String a, String b) {
    final ap = a.split('-');
    final bp = b.split('-');
    final year = (int.tryParse(bp.first) ?? -1).compareTo(int.tryParse(ap.first) ?? -1);
    if (year != 0) return year;
    final aSemester = ap.length > 1 ? int.tryParse(ap[1]) ?? -1 : -1;
    final bSemester = bp.length > 1 ? int.tryParse(bp[1]) ?? -1 : -1;
    return bSemester.compareTo(aSemester);
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}
