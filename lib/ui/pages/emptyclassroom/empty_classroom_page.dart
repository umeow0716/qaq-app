import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/connector/course_connector.dart';
import 'package:qaq_app/src/model/course/course_class_json.dart';
import 'package:qaq_app/src/model/coursetable/course_table_json.dart';
import 'package:qaq_app/src/model/coursetable/empty_classroom_cache.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/task/course/course_system_task.dart';
import 'package:qaq_app/src/task/course/empty_classroom_build_task.dart';
import 'package:qaq_app/src/task/task.dart';
import 'package:qaq_app/src/util/language_util.dart';

class EmptyClassroomPage extends StatefulWidget {
  const EmptyClassroomPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<EmptyClassroomPage> createState() => _EmptyClassroomPageState();
}

class _EmptyClassroomPageState extends State<EmptyClassroomPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _clockTimer;

  List<SemesterJson> _semesters = const <SemesterJson>[];
  SemesterJson? _semester;
  EmptyClassroomCacheJson? _cache;
  late Day _selectedDay;
  bool _onlyCurrentlyFree = false;
  bool _initializing = true;
  bool _building = false;
  SemesterJson? _buildingSemester;
  SemesterJson? _pendingBuildSemester;
  bool _pendingForceRebuild = false;
  String? _error;
  double? _progress;
  String? _progressText;

  bool get _english => LanguageUtil.getLangIndex() == LangEnum.en;
  static const String _language = 'zh';

  String _text(String zh, String en) => _english ? en : zh;

  @override
  void initState() {
    super.initState();
    _selectedDay = EmptyClassroomPeriod.dayFromDateTime(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _error = null;
    });

    try {
      if (LocalStorage.instance.getAccount().trim().isEmpty) {
        throw StateError(_text('請先登入後再使用尋找空教室。', 'Please sign in before finding empty classrooms.'));
      }

      final sessionTask = CourseSystemTask<void>('EmptyClassroom')..openLoadingDialog = false;
      if (await sessionTask.execute() != TaskStatus.success) {
        throw StateError(_text('無法登入課程系統。', 'Unable to sign in to the course system.'));
      }

      final storage = LocalStorage.instance;
      final fetchedSemesters = await CourseConnector.getClassroomSemesters();
      var semesters = fetchedSemesters ?? <SemesterJson>[];
      if (semesters.isEmpty) {
        semesters = EmptyClassroomSemesterPolicy.newestTwo(
          storage
              .getEmptyClassroomCaches()
              .where((cache) => cache.language == _language)
              .map((cache) => cache.courseSemester),
        );
      }
      semesters = EmptyClassroomSemesterPolicy.newestTwo(semesters);
      final current = semesters.isEmpty ? null : semesters.first;
      if (current == null) {
        throw StateError(
          _text('無法從課程系統首頁取得可用學期。', 'Unable to determine available semesters from the course system home page.'),
        );
      }

      await storage.retainEmptyClassroomCaches(semesters: semesters, language: _language);
      final cache = storage.getEmptyClassroomCache(current, _language);

      if (!mounted) return;
      setState(() {
        _semesters = semesters;
        _semester = current;
        _cache = cache;
        _initializing = false;
      });

      if (cache == null || !cache.complete) {
        await _buildTable(forceRebuild: false);
      }
    } catch (error, stackTrace) {
      Log.eWithStack('Empty classroom initialization failed: $error', stackTrace);
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _selectSemester(SemesterJson semester) async {
    if (semester == _semester) return;

    final cache = LocalStorage.instance.getEmptyClassroomCache(semester, _language);
    if (!mounted) return;
    setState(() {
      _semester = semester;
      _cache = cache;
      _error = null;
    });

    if (cache != null && cache.complete) {
      if (_building) {
        _pendingBuildSemester = null;
        _pendingForceRebuild = false;
      }
      return;
    }

    if (_building) {
      if (semester == _buildingSemester) {
        _pendingBuildSemester = null;
        _pendingForceRebuild = false;
      } else {
        _pendingBuildSemester = semester;
        _pendingForceRebuild = false;
      }
      return;
    }

    await _buildTable(forceRebuild: false, semester: semester);
  }

  Future<void> _buildTable({required bool forceRebuild, SemesterJson? semester}) async {
    final targetSemester = semester ?? _semester;
    if (targetSemester == null) return;

    if (_building) {
      if (targetSemester != _buildingSemester) {
        _pendingBuildSemester = targetSemester;
        _pendingForceRebuild = _pendingForceRebuild || forceRebuild;
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _building = true;
      _buildingSemester = targetSemester;
      _error = null;
      _progress = 0;
      _progressText = '0/0';
    });

    try {
      final cache = await EmptyClassroomBuildTask.build(
        semester: targetSemester,
        forceRebuild: forceRebuild,
        onProgress: (completed, total) {
          if (!mounted || _buildingSemester != targetSemester) return;
          final progress = total == 0 ? 0.0 : completed / total;
          final progressText = '$completed/$total';
          setState(() {
            _progress = progress;
            _progressText = progressText;
            if (_semester == targetSemester) {
              _cache = LocalStorage.instance.getEmptyClassroomCache(targetSemester, _language);
            }
          });
        },
      );

      if (!mounted || _semester != targetSemester) return;
      setState(() {
        _cache = cache;
        if (cache == null) {
          _error = _text('無法取得教室資料。', 'Unable to load classroom data.');
        } else if (!cache.complete) {
          _error = _text(
            '建表尚未完成；已完成的部分已保留，下次進入或重新整理會繼續。',
            'The table is incomplete. Completed rooms were saved and the next visit or refresh will resume it.',
          );
        }
      });
    } catch (error, stackTrace) {
      Log.eWithStack('Empty classroom build failed: $error', stackTrace);
      if (mounted && _semester == targetSemester) {
        setState(() {
          _cache = LocalStorage.instance.getEmptyClassroomCache(targetSemester, _language);
          _error = forceRebuild && (_cache?.complete ?? false)
              ? _text('重新建表失敗，已保留原本的完整快取。', 'Rebuild failed. The previous complete cache was kept.')
              : _text(
                  '建表中斷；已完成的部分已保留，下次會自動續建。',
                  'Building was interrupted. Completed rooms were saved and will resume automatically.',
                );
        });
      }
    } finally {
      final pendingSemester = _pendingBuildSemester;
      final pendingForceRebuild = _pendingForceRebuild;
      _pendingBuildSemester = null;
      _pendingForceRebuild = false;

      if (mounted) {
        setState(() {
          _building = false;
          _buildingSemester = null;
          _progress = null;
          _progressText = null;
        });

        if (pendingSemester != null) {
          final pendingCache = LocalStorage.instance.getEmptyClassroomCache(pendingSemester, _language);
          if (pendingForceRebuild || pendingCache == null || !pendingCache.complete) {
            unawaited(_buildTable(forceRebuild: pendingForceRebuild, semester: pendingSemester));
          }
        }
      }
    }
  }

  List<EmptyClassroomRoomJson> get _visibleRooms {
    final rooms = (_cache?.rooms ?? const <EmptyClassroomRoomJson>[]).where((room) => room.built).toList();
    final query = _searchController.text.trim().toLowerCase();
    final currentSection = EmptyClassroomPeriod.at(DateTime.now());

    return rooms
        .where((room) {
          if (query.isNotEmpty) {
            final haystack = '${room.name} ${room.fullName}'.toLowerCase();
            if (!haystack.contains(query)) return false;
          }
          if (_onlyCurrentlyFree && currentSection != null && room.isOccupied(_selectedDay, currentSection)) {
            return false;
          }
          return true;
        })
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final semester = _semester;
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(_text('尋找空教室', 'Find Empty Classrooms')),
              actions: [
                IconButton(
                  tooltip: _text('重新建表', 'Rebuild table'),
                  onPressed: _building || semester == null ? null : () => _buildTable(forceRebuild: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: _initializing ? _buildInitializing() : _buildContent(),
    );
  }

  Widget _buildInitializing() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(_text('正在偵測可用學期…', 'Detecting available semesters…')),
      ],
    ),
  );

  Widget _buildContent() {
    final semester = _semester;
    final rooms = _visibleRooms;
    final cache = _cache;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          if (widget.embedded)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _text('搜尋教室名稱', 'Search classroom name'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _text('重新建表', 'Rebuild table'),
                  onPressed: _building || semester == null ? null : () => _buildTable(forceRebuild: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          else
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _text('搜尋教室名稱', 'Search classroom name'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          const SizedBox(height: 10),
          if (widget.embedded)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in _semesters) ...[
                    _SemesterChip(
                      label: '${option.year}-${option.semester}',
                      selected: option == semester,
                      onPressed: () => _selectSemester(option),
                    ),
                    const SizedBox(width: 8),
                  ],
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _onlyCurrentlyFree = !_onlyCurrentlyFree),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(
                            scale: 0.88,
                            child: Checkbox(
                              value: _onlyCurrentlyFree,
                              onChanged: (value) => setState(() => _onlyCurrentlyFree = value ?? false),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(_text('僅顯示目前空教室', 'Show only classrooms free right now')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final day in _dayOrder) ...[
                    _DayChip(
                      label: _dayLabel(day),
                      selected: day == _selectedDay,
                      onPressed: () => setState(() => _selectedDay = day),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final option in _semesters)
                  _SemesterChip(
                    label: '${option.year}-${option.semester}',
                    selected: option == semester,
                    onPressed: () => _selectSemester(option),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _onlyCurrentlyFree = !_onlyCurrentlyFree),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 0.88,
                          child: Checkbox(
                            value: _onlyCurrentlyFree,
                            onChanged: (value) => setState(() => _onlyCurrentlyFree = value ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(_text('僅顯示目前空教室', 'Show only classrooms free right now')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final day in _dayOrder) ...[
                    _DayChip(
                      label: _dayLabel(day),
                      selected: day == _selectedDay,
                      onPressed: () => setState(() => _selectedDay = day),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _buildLegend(),
          if (_building) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _text(
                  '正在建立 ${_semesterLabel(_buildingSemester)} 教室使用表',
                  'Building classroom availability for ${_semesterLabel(_buildingSemester)}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerRight, child: Text(_progressText ?? '')),
          ],
          if (_error != null) ...[const SizedBox(height: 10), _buildNotice(_error!)],
          if (cache != null && !cache.complete && cache.rooms.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _text(
                  '已建立 ${cache.builtCount}/${cache.rooms.length} 間教室',
                  'Built ${cache.builtCount}/${cache.rooms.length} classrooms',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: rooms.isEmpty
                ? Center(
                    child: Text(
                      _building
                          ? _text('正在建立教室資料…', 'Building classroom data…')
                          : _text('沒有符合條件的教室', 'No classrooms match the filters'),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1000
                          ? 3
                          : constraints.maxWidth >= 650
                          ? 2
                          : 1;
                      final childAspectRatio = columns == 1
                          ? 2.15
                          : columns == 2
                          ? 2.35
                          : 2.55;
                      return GridView.builder(
                        padding: const EdgeInsets.only(bottom: 20),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: widget.embedded ? 8 : 12,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemCount: rooms.length,
                        itemBuilder: (context, index) => _RoomCard(
                          room: rooms[index],
                          selectedDay: _selectedDay,
                          currentSection: EmptyClassroomPeriod.at(DateTime.now()),
                          highlightCurrent: _selectedDay == EmptyClassroomPeriod.dayFromDateTime(DateTime.now()),
                          compactVerticalSpacing: columns > 1,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _LegendDot(color: colorScheme.onSurface.withValues(alpha: 0.10), label: _text('空堂', 'Free')),
        _LegendDot(color: colorScheme.secondary, label: _text('有課', 'Occupied')),
        _LegendDot(color: Colors.transparent, borderColor: colorScheme.primary, label: _text('目前節次', 'Current period')),
      ],
    );
  }

  Widget _buildNotice(String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }

  String _semesterLabel(SemesterJson? semester) => semester == null ? '' : '${semester.year}-${semester.semester}';

  String _dayLabel(Day day) {
    if (_english) {
      return switch (day) {
        Day.Sunday => 'Sun',
        Day.Monday => 'Mon',
        Day.Tuesday => 'Tue',
        Day.Wednesday => 'Wed',
        Day.Thursday => 'Thu',
        Day.Friday => 'Fri',
        Day.Saturday => 'Sat',
        Day.UnKnown => '?',
      };
    }
    return switch (day) {
      Day.Sunday => '日',
      Day.Monday => '一',
      Day.Tuesday => '二',
      Day.Wednesday => '三',
      Day.Thursday => '四',
      Day.Friday => '五',
      Day.Saturday => '六',
      Day.UnKnown => '?',
    };
  }

  static const List<Day> _dayOrder = <Day>[
    Day.Sunday,
    Day.Monday,
    Day.Tuesday,
    Day.Wednesday,
    Day.Thursday,
    Day.Friday,
    Day.Saturday,
  ];
}

class _SemesterChip extends StatelessWidget {
  const _SemesterChip({required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 60, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.selectedDay,
    required this.currentSection,
    required this.highlightCurrent,
    required this.compactVerticalSpacing,
  });

  final EmptyClassroomRoomJson room;
  final Day selectedDay;
  final SectionNumber? currentSection;
  final bool highlightCurrent;
  final bool compactVerticalSpacing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room.name, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (room.fullName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(room.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
            ],
            if (room.capacity.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_alt_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    room.capacity,
                    style: textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
            if (compactVerticalSpacing) const SizedBox(height: 12) else const Spacer(),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final section in EmptyClassroomPeriod.order)
                  _PeriodDot(
                    label: EmptyClassroomPeriod.label(section),
                    occupied: room.isOccupied(selectedDay, section),
                    current: highlightCurrent && section == currentSection,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodDot extends StatelessWidget {
  const _PeriodDot({required this.label, required this.occupied, required this.current});

  final String label;
  final bool occupied;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = occupied ? colorScheme.secondary : colorScheme.onSurface.withValues(alpha: 0.10);
    final foreground = occupied ? colorScheme.onSecondary : colorScheme.onSurface.withValues(alpha: 0.58);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: current ? Border.all(color: colorScheme.primary, width: 2.5) : null,
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontSize: 11, fontWeight: occupied ? FontWeight.w800 : FontWeight.w600),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label, this.borderColor});

  final Color color;
  final Color? borderColor;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: borderColor == null ? null : Border.all(color: borderColor!, width: 2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
