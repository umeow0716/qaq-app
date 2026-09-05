import 'package:json_annotation/json_annotation.dart';

part 'ap_tree_json.g.dart';

@JsonSerializable(createToJson: false)
class APTreeJson {
  @JsonKey(name: 'apList')
  List<APListJson> apList;

  @JsonKey(name: 'parentDn')
  String parentDn;

  APTreeJson(List<APListJson>? apList, String? parentDn)
      : apList = apList ?? <APListJson>[],
        parentDn = parentDn ?? '';

  factory APTreeJson.fromJson(Map<String, dynamic> srcJson) => _$APTreeJsonFromJson(srcJson);
}

@JsonSerializable(createToJson: false)
class APListJson {
  @JsonKey(name: 'apDn')
  String apDn;
  @JsonKey(name: 'icon')
  String icon;
  @JsonKey(name: 'urlSource')
  String urlSource;
  @JsonKey(name: 'description')
  String description;
  @JsonKey(name: 'type')
  String type;
  @JsonKey(name: 'urlLink')
  String urlLink;

  APListJson(String? apDn, String? description, String? icon, String? type, String? urlLink, String? urlSource)
      : apDn = apDn ?? '',
        description = description ?? '',
        icon = icon ?? '',
        type = type ?? '',
        urlLink = urlLink ?? '',
        urlSource = urlSource ?? '';

  factory APListJson.fromJson(Map<String, dynamic> srcJson) => _$APListJsonFromJson(srcJson);
}
