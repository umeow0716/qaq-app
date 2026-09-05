import 'package:json_annotation/json_annotation.dart';

part 'ntut_calendar_json.g.dart';

List<NTUTCalendarJson> getNTUTCalendarJsonList(List<dynamic> list) {
  final result = <NTUTCalendarJson>[];
  for (final item in list) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final value = NTUTCalendarJson.fromJson(item);
    if (value.calTitle.isNotEmpty) {
      result.add(value);
    }
  }
  return result;
}

@JsonSerializable()
class NTUTCalendarJson {
  @JsonKey(name: 'id')
  int id;
  @JsonKey(name: 'calStart')
  int calStart;
  @JsonKey(name: 'calEnd')
  int calEnd;
  @JsonKey(name: 'allDay')
  String allDay;
  @JsonKey(name: 'calTitle')
  String calTitle;
  @JsonKey(name: 'calPlace')
  String calPlace;
  @JsonKey(name: 'calContent')
  String calContent;
  @JsonKey(name: 'calColor')
  String calColor;
  @JsonKey(name: 'ownerId')
  String ownerId;
  @JsonKey(name: 'ownerName')
  String ownerName;
  @JsonKey(name: 'creatorId')
  String creatorId;
  @JsonKey(name: 'creatorName')
  String creatorName;
  @JsonKey(name: 'modifierId')
  String modifierId;
  @JsonKey(name: 'modifierName')
  String modifierName;
  @JsonKey(name: 'modifyDate')
  int modifyDate;
  @JsonKey(name: 'hasBeenDeleted')
  int hasBeenDeleted;
  @JsonKey(name: 'calInviteeList')
  List<dynamic> calInviteeList;
  @JsonKey(name: 'calAlertList')
  List<dynamic> calAlertList;

  NTUTCalendarJson(
    int? id,
    int? calStart,
    int? calEnd,
    String? allDay,
    String? calTitle,
    String? calPlace,
    String? calContent,
    String? calColor,
    String? ownerId,
    String? ownerName,
    String? creatorId,
    String? creatorName,
    String? modifierId,
    String? modifierName,
    int? modifyDate,
    int? hasBeenDeleted,
    List<dynamic>? calInviteeList,
    List<dynamic>? calAlertList,
  )   : id = id ?? 0,
        calStart = calStart ?? 0,
        calEnd = calEnd ?? 0,
        allDay = allDay ?? '',
        calTitle = calTitle ?? '',
        calPlace = calPlace ?? '',
        calContent = calContent ?? '',
        calColor = calColor ?? '',
        ownerId = ownerId ?? '',
        ownerName = ownerName ?? '',
        creatorId = creatorId ?? '',
        creatorName = creatorName ?? '',
        modifierId = modifierId ?? '',
        modifierName = modifierName ?? '',
        modifyDate = modifyDate ?? 0,
        hasBeenDeleted = hasBeenDeleted ?? 0,
        calInviteeList = calInviteeList ?? <dynamic>[],
        calAlertList = calAlertList ?? <dynamic>[];

  factory NTUTCalendarJson.fromJson(Map<String, dynamic> srcJson) => _$NTUTCalendarJsonFromJson(srcJson);

  @override
  String toString() => calTitle;

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(calStart, isUtc: true).add(const Duration(hours: 8));

  DateTime get endTime => DateTime.fromMillisecondsSinceEpoch(calEnd, isUtc: true).add(const Duration(hours: 8));
}
