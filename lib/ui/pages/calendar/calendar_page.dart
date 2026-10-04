import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:qaq_app/src/controllers/calendar_controller.dart';
import 'package:qaq_app/src/model/ntut/ntut_calendar_json.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/ui/pages/calendar/calendar_detail_dialog.dart';
import 'package:table_calendar/table_calendar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  NTUTCalendarJson? _selectedDesktopEvent;
  late final Future<void> _initialLoadFuture;

  bool get _isDesktop => Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _initialLoadFuture = CalendarController.instance.findFirstEventsFromToday(
      showLoadingDialog: !_isDesktop,
    );
  }

  Widget _buildEventList(BuildContext context, List<NTUTCalendarJson> selectedEvents) {
    final eventBorderColor = Theme.of(context).colorScheme.onSurface;
    return ListView.builder(
      itemCount: selectedEvents.length,
      itemBuilder: (context, index) {
        final event = selectedEvents[index];
        return Padding(
          padding: const EdgeInsets.all(4.0),
          child: Card(
            child: ListTile(
              title: Text(event.calTitle),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: eventBorderColor),
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => Get.dialog(CalendarDetailDialog(calendarDetail: event), barrierDismissible: true),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableCalendar(CalendarController controller, {bool desktop = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return TableCalendar(
      focusedDay: controller.focusDayRx.value,
      firstDay: controller.firstDay,
      lastDay: controller.lastDay,
      locale: controller.currentCalendarLocaleString,
      calendarFormat: controller.calendarFormatRx.value,
      eventLoader: controller.getEventsFromDay,
      holidayPredicate: controller.isHoliday,
      selectedDayPredicate: controller.isSelectingSelectedDay,
      startingDayOfWeek: StartingDayOfWeek.monday,
      onFormatChanged: controller.onFormatChanged,
      onDaySelected: (selectedDay, focusedDay) {
        controller.onDaySelected(selectedDay, focusedDay);
        if (_selectedDesktopEvent != null && mounted) {
          setState(() => _selectedDesktopEvent = null);
        }
      },
      onPageChanged: (focusedDay) => unawaited(
        controller.onPageChanged(focusedDay, showLoadingDialog: !desktop),
      ),
      pageAnimationEnabled: true,
      pageAnimationDuration: desktop ? const Duration(milliseconds: 180) : const Duration(milliseconds: 300),
      pageAnimationCurve: desktop ? Curves.easeOutCubic : Curves.easeOut,
      formatAnimationDuration: desktop ? const Duration(milliseconds: 180) : const Duration(milliseconds: 200),
      formatAnimationCurve: desktop ? Curves.easeOutCubic : Curves.linear,
      headerStyle: desktop
          ? HeaderStyle(
              titleCentered: true,
              formatButtonVisible: false,
              formatButtonTextStyle: TextStyle(color: colorScheme.onPrimary, fontSize: 15.0),
              formatButtonDecoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(16.0),
              ),
            )
          : HeaderStyle(
              formatButtonTextStyle: const TextStyle().copyWith(color: Colors.white, fontSize: 15.0),
              formatButtonDecoration: BoxDecoration(
                color: Colors.deepOrange[400],
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
      calendarStyle: desktop
          ? CalendarStyle(
              isTodayHighlighted: true,
              selectedDecoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
              selectedTextStyle: TextStyle(color: colorScheme.onPrimary),
              todayDecoration: BoxDecoration(color: colorScheme.tertiary, shape: BoxShape.circle),
              todayTextStyle: TextStyle(color: colorScheme.onTertiary),
              outsideDaysVisible: false,
              weekendTextStyle: TextStyle(color: colorScheme.error),
              markerDecoration: BoxDecoration(color: colorScheme.secondary, shape: BoxShape.circle),
            )
          : const CalendarStyle(
              isTodayHighlighted: true,
              selectedDecoration: BoxDecoration(color: Colors.lightBlueAccent, shape: BoxShape.circle),
              selectedTextStyle: TextStyle(color: Colors.white),
              todayDecoration: BoxDecoration(color: Colors.deepOrange, shape: BoxShape.circle),
              todayTextStyle: TextStyle(color: Colors.white),
              outsideDaysVisible: false,
              weekendTextStyle: TextStyle(color: Colors.red),
              markerDecoration: BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
            ),
      daysOfWeekStyle: desktop
          ? DaysOfWeekStyle(
              weekdayStyle: const TextStyle(height: 1),
              weekendStyle: TextStyle(height: 1, color: colorScheme.error),
            )
          : const DaysOfWeekStyle(
              weekdayStyle: TextStyle(height: 1),
              weekendStyle: TextStyle(height: 1, color: Colors.red),
            ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialLoadFuture,
    builder: (context, _) => _isDesktop ? _buildDesktop() : _buildMobile(),
  );

  Widget _buildMobile() => Scaffold(
    appBar: AppBar(title: Text(R.current.calendar)),
    body: Obx(() {
      final controller = CalendarController.instance;
      return Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          _buildTableCalendar(controller),
          const SizedBox(height: 16.0),
          Expanded(child: _buildEventList(context, controller.selectedEventsRx)),
        ],
      );
    }),
  );

  Widget _buildDesktop() {
    final controller = CalendarController.instance;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: Obx(() => _buildTableCalendar(controller, desktop: true)),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Obx(
                      () => controller.isLoadingRx.value
                          ? const _DesktopCalendarLoadingBadge()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
              ),
              child: Obx(() {
                final selectedEvents = controller.selectedEventsRx;
                final selectedDay = controller.selectedDayRx.value;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat.yMMMMd(controller.currentCalendarLocaleString).format(selectedDay),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 3,
                        child: selectedEvents.isEmpty
                            ? Center(
                                child: Icon(
                                  Icons.event_busy_outlined,
                                  size: 34,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                                ),
                              )
                            : ListView.separated(
                                itemCount: selectedEvents.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final event = selectedEvents[index];
                                  final selected = identical(event, _selectedDesktopEvent);
                                  return Material(
                                    color: selected ? colorScheme.primaryContainer : colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => setState(() => _selectedDesktopEvent = event),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                        child: Row(
                                          children: [
                                            Icon(Icons.event_outlined, size: 18, color: colorScheme.primary),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Text(
                                                event.calTitle,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (_selectedDesktopEvent != null) ...[
                        const SizedBox(height: 12),
                        Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
                        const SizedBox(height: 8),
                        Expanded(flex: 2, child: _buildDesktopEventDetail(_selectedDesktopEvent!)),
                      ],
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopEventDetail(NTUTCalendarJson event) {
    final locale = CalendarController.instance.currentCalendarLocaleString;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.calTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _EventMeta(
            icon: Icons.access_time,
            text: '${DateFormat.yMMMd(locale).format(event.startTime)} – ${DateFormat.yMMMd(locale).format(event.endTime)}',
          ),
          if (event.calPlace.trim().isNotEmpty) _EventMeta(icon: Icons.place_outlined, text: event.calPlace.trim()),
          if (event.creatorName.trim().isNotEmpty)
            _EventMeta(icon: Icons.person_outline, text: event.creatorName.trim()),
          if (event.calContent.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(event.calContent.trim()),
          ],
        ],
      ),
    );
  }
}

class _DesktopCalendarLoadingBadge extends StatelessWidget {
  const _DesktopCalendarLoadingBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: const SizedBox(
        width: 42,
        height: 42,
        child: Padding(
          padding: EdgeInsets.all(11),
          child: RepaintBoundary(
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      ),
    );
  }
}

class _EventMeta extends StatelessWidget {
  const _EventMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
