import 'package:json_annotation/json_annotation.dart';

part 'ischool_plus_announcement_json.g.dart';

@JsonSerializable(createToJson: false)
class ISchoolPlusAnnouncementInfoJson {
  @JsonKey(name: 'total')
  int total;
  @JsonKey(name: 'code')
  int code;
  @JsonKey(name: 'total_rows')
  String totalRows;
  @JsonKey(name: 'limit_rows')
  int limitRows;
  @JsonKey(name: 'current_page')
  String currentPage;
  @JsonKey(name: 'editEnable')
  String editEnable;
  @JsonKey(name: 'data')
  String data;

  ISchoolPlusAnnouncementInfoJson(
    int? total,
    int? code,
    String? totalRows,
    int? limitRows,
    String? currentPage,
    String? editEnable,
    String? data,
  ) : total = total ?? 0,
      code = code ?? 0,
      totalRows = totalRows ?? '',
      limitRows = limitRows ?? 0,
      currentPage = currentPage ?? '',
      editEnable = editEnable ?? '',
      data = data ?? '';

  factory ISchoolPlusAnnouncementInfoJson.fromJson(Map<String, dynamic> srcJson) =>
      _$ISchoolPlusAnnouncementInfoJsonFromJson(srcJson);
}

@JsonSerializable(createToJson: false)
class ISchoolPlusAnnouncementJson {
  String token = '';
  String bid = '';
  String nid = '';

  @JsonKey(name: 'boardid')
  String boardid;
  @JsonKey(name: 'encbid')
  String encbid;
  @JsonKey(name: 'node')
  String node;
  @JsonKey(name: 'encnid')
  String encnid;
  @JsonKey(name: 'cid')
  String cid;
  @JsonKey(name: 'enccid')
  String enccid;
  @JsonKey(name: 'poster')
  String poster;
  @JsonKey(name: 'realname')
  String realname;
  @JsonKey(name: 'cpic')
  String cpic;
  @JsonKey(name: 'subject')
  String subject;
  @JsonKey(name: 'postdate')
  String postdate;
  @JsonKey(name: 'postdatelen')
  String postdatelen;
  @JsonKey(name: 'postcontent')
  String postcontent;
  @JsonKey(name: 'postcontenttext')
  String postcontenttext;
  @JsonKey(name: 'hit')
  String hit;
  @JsonKey(name: 'qrcode_url')
  String qrcodeUrl;
  @JsonKey(name: 'floor')
  int floor;
  @JsonKey(name: 'attach')
  String attach;
  @JsonKey(name: 'postfilelink')
  String postfilelink;
  @JsonKey(name: 'attachment')
  String attachment;
  @JsonKey(name: 'n')
  String n;
  @JsonKey(name: 's')
  String s;
  @JsonKey(name: 'readflag')
  int readflag;
  @JsonKey(name: 'postRoles')
  String postRoles;

  ISchoolPlusAnnouncementJson(
    String? boardid,
    String? encbid,
    String? node,
    String? encnid,
    String? cid,
    String? enccid,
    String? poster,
    String? realname,
    String? cpic,
    String? subject,
    String? postdate,
    String? postdatelen,
    String? postcontent,
    String? postcontenttext,
    String? hit,
    String? qrcodeUrl,
    int? floor,
    String? attach,
    String? postfilelink,
    String? attachment,
    String? n,
    String? s,
    int? readflag,
    String? postRoles,
  ) : boardid = boardid ?? '',
      encbid = encbid ?? '',
      node = node ?? '',
      encnid = encnid ?? '',
      cid = cid ?? '',
      enccid = enccid ?? '',
      poster = poster ?? '',
      realname = realname ?? '',
      cpic = cpic ?? '',
      subject = subject ?? '',
      postdate = postdate ?? '',
      postdatelen = postdatelen ?? '',
      postcontent = postcontent ?? '',
      postcontenttext = postcontenttext ?? '',
      hit = hit ?? '',
      qrcodeUrl = qrcodeUrl ?? '',
      floor = floor ?? 0,
      attach = attach ?? '',
      postfilelink = postfilelink ?? '',
      attachment = attachment ?? '',
      n = n ?? '',
      s = s ?? '',
      readflag = readflag ?? 0,
      postRoles = postRoles ?? '';

  factory ISchoolPlusAnnouncementJson.fromJson(Map<String, dynamic> srcJson) =>
      _$ISchoolPlusAnnouncementJsonFromJson(srcJson);
}
