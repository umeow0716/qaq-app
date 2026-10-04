import 'dart:collection';

import 'package:qaq_app/src/model/ntut/ntut_calendar_json.dart';
import 'package:qaq_app/src/task/ntut/ntut_calendar_task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/src/util/language_util.dart';
import 'package:get/get_rx/get_rx.dart';
import 'package:get/get_state_manager/get_state_manager.dart';
import 'package:table_calendar/table_calendar.dart';

class CalendarController extends GetxController {
  static final CalendarController instance = CalendarController();

  final Map<DateTime, List<NTUTCalendarJson>> knownHolidays = {
    // TODO: Define the source of holidays in a correct way.
    // FIXME: The type of holiday should not be `NTUTCalendarJson`.
  };

  final knownSchoolEvents = LinkedHashMap<DateTime, List<NTUTCalendarJson>>(equals: isSameDay);

  final selectedEventsRx = <NTUTCalendarJson>[].obs;
  final isLoadingRx = false.obs;
  final calendarFormatRx = CalendarFormat.month.obs;
  final focusDayRx = DateTime.now().toLocal().obs;
  final selectedDayRx = DateTime.now().toLocal().obs;

  final firstDay = DateTime(1990);
  final lastDay = DateTime(2099);

  final _storedMonthSet = <DateTime>{};
  final _pendingMonthLoads = <DateTime, Future<void>>{};
  int _activeLoads = 0;

  String get currentCalendarLocaleString => (LanguageUtil.getLangIndex() == LangEnum.zh) ? "zh_TW" : "en_US";

  List<NTUTCalendarJson> getEventsFromDay(DateTime day) => knownSchoolEvents[day] ?? const [];

  bool isHoliday(DateTime day) => knownHolidays.containsKey(day);

  bool isSelectingSelectedDay(DateTime day) => isSameDay(selectedDayRx.value, day);

  void onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(selectedDayRx.value, selectedDay)) {
      selectedDayRx.value = selectedDay;
      focusDayRx.value = focusedDay;
      selectedEventsRx.value = getEventsFromDay(selectedDay);
      update();
    }
  }

  Future<void> onPageChanged(DateTime focusedDay, {bool showLoadingDialog = true}) async {
    focusDayRx.value = focusedDay;
    await _getMonthlyEvents(startTime: focusedDay, showLoadingDialog: showLoadingDialog);

    // change the selected day to the first day of current month.
    selectedDayRx.value = DateTime(focusedDay.year, focusedDay.month, 1).toUTCLocal();

    // change the selected events to the first day of current month.
    selectedEventsRx.value = getEventsFromDay(selectedDayRx.value);

    update();
  }

  void onFormatChanged(CalendarFormat format) {
    calendarFormatRx.value = format;
    update();
  }

  Future<void> findFirstEventsFromToday({bool showLoadingDialog = true}) async {
    final now = DateTime.now();
    final firstDayOfCurrentMonth = DateTime(now.year, now.month, 1);

    // Only preserve the day part of the date.
    final today = DateTime(now.year, now.month, now.day).toUTCLocal();

    if (!_storedMonthSet.contains(firstDayOfCurrentMonth)) {
      await _getMonthlyEvents(startTime: today, showLoadingDialog: showLoadingDialog);
    }
    selectedEventsRx.value = getEventsFromDay(today);
  }

  /// Get the events of the month of the given [startTime].
  /// If the [startTime] is not the first day of the month, the [startTime] will be set to the first day of the month.
  Future<void> _getMonthlyEvents({required DateTime startTime, bool showLoadingDialog = true}) {
    // Since the backend api only supports monthly query, we need to query the whole month.
    const fixedEventRequestDay = 1;
    final firstDayOfTargetMonth = DateTime(startTime.year, startTime.month, fixedEventRequestDay);

    if (_storedMonthSet.contains(firstDayOfTargetMonth)) {
      return Future<void>.value();
    }

    final pending = _pendingMonthLoads[firstDayOfTargetMonth];
    if (pending != null) {
      return pending;
    }

    late final Future<void> load;
    load = _loadMonthlyEvents(
      firstDayOfTargetMonth: firstDayOfTargetMonth,
      showLoadingDialog: showLoadingDialog,
    ).whenComplete(() {
      if (identical(_pendingMonthLoads[firstDayOfTargetMonth], load)) {
        _pendingMonthLoads.remove(firstDayOfTargetMonth);
      }
    });
    _pendingMonthLoads[firstDayOfTargetMonth] = load;
    return load;
  }

  Future<void> _loadMonthlyEvents({
    required DateTime firstDayOfTargetMonth,
    required bool showLoadingDialog,
  }) async {
    // Use `zero` to represent the last day of the month.
    const fixedEventRequestLastDayOfAnyMonth = 0;
    final lastDayOfTargetMonth = DateTime(
      firstDayOfTargetMonth.year,
      firstDayOfTargetMonth.month + 1,
      fixedEventRequestLastDayOfAnyMonth,
    );

    final taskFlow = TaskFlow();
    final calendarTask = NTUTCalendarTask(firstDayOfTargetMonth, lastDayOfTargetMonth)
      ..openLoadingDialog = showLoadingDialog;
    taskFlow.addTask(calendarTask);

    _activeLoads++;
    isLoadingRx.value = true;
    try {
      if (await taskFlow.start()) {
        final schoolEvents = calendarTask.result;
        if (schoolEvents == null) {
          return;
        }

        for (final nonAddedSchoolEvent in schoolEvents) {
          final eventTime = nonAddedSchoolEvent.startTime.toLocal();
          if (eventTime.isBefore(firstDayOfTargetMonth) || eventTime.isAfter(lastDayOfTargetMonth)) {
            continue;
          }

          knownSchoolEvents.update(
            eventTime,
            (addedEvents) => [...addedEvents, nonAddedSchoolEvent],
            ifAbsent: () => [nonAddedSchoolEvent],
          );
        }

        _storedMonthSet.add(firstDayOfTargetMonth);
      }
    } finally {
      _activeLoads--;
      isLoadingRx.value = _activeLoads > 0;
    }
  }

}

extension on DateTime {
  static const taipeiTimeZoneHours = 8;

  /// Convert the [DateTime] to the [DateTime] in the Asia/Taipei time zone.
  /// You may not use `toLocal()` here, since the `toString()` method of `DateTime` will generate different results with the UTC time's.
  ///
  /// In specific terms, UTC time is represented by a 'Z' character that is appended to the string representation of the time.
  /// For example, if the current time in UTC is 3:00 PM, it might be represented as "15:00Z".
  ///
  /// It is important to note that the keys for the `knownSchoolEvents` map use UTC time.
  /// If a non-UTC time is used in the map query, it may not be able to find the corresponding value.
  DateTime toUTCLocal() => toUtc().add(const Duration(hours: taipeiTimeZoneHours));
}
