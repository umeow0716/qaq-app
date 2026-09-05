import 'package:flutter/material.dart';
import 'package:flutter_app/src/model/course/course_score_json.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/src/store/local_storage.dart';
import 'package:flutter_app/src/task/course/course_credit_info_task.dart';
import 'package:flutter_app/src/task/course/course_department_task.dart';
import 'package:flutter_app/src/task/course/course_division_task.dart';
import 'package:flutter_app/src/task/course/course_year_task.dart';
import 'package:flutter_app/src/task/task_flow.dart';
import 'package:get/get.dart';

class GraduationPicker {
  late GraduationPickerWidget _dialog;
  BuildContext? _dismissingContext;
  bool _barrierDismissible = true;
  bool _isShowing = false;

  GraduationPicker(BuildContext context, {bool? isDismissible}) {
    _dismissingContext = context;
    _barrierDismissible = isDismissible ?? _barrierDismissible; //是否之支援返回關閉
  }

  bool isShowing() {
    return _isShowing;
  }

  void dismiss() {
    if (_isShowing) {
      try {
        _isShowing = false;
        final context = _dismissingContext;
        if (context != null && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } catch (_) {}
    }
  }

  Future<bool> hide() {
    if (_isShowing) {
      try {
        _isShowing = false;
        final context = _dismissingContext;
        if (context == null) return Future.value(false);
        Navigator.of(context).pop(true);
        return Future.value(true);
      } catch (_) {
        return Future.value(false);
      }
    } else {
      return Future.value(false);
    }
  }

  Future<bool> show(void Function(GraduationInformationJson) finishCallBack) async {
    if (!_isShowing) {
      try {
        _dialog = const GraduationPickerWidget();
        Get.dialog<GraduationInformationJson>(
          WillPopScope(
              onWillPop: () async => _barrierDismissible,
              child: Dialog(
                  insetAnimationDuration: const Duration(milliseconds: 100),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                  child: _dialog)),
          barrierDismissible: false,
        ).then((value) {
          if (value != null) finishCallBack(value);
        });
        // Delaying the function for 200 milliseconds
        // [Default transitionDuration of DialogRoute]
        await Future.delayed(const Duration(milliseconds: 200));
        _isShowing = true;
        return true;
      } catch (_) {
        return false;
      }
    } else {
      return false;
    }
  }
}

class GraduationPickerWidget extends StatefulWidget {
  const GraduationPickerWidget({Key? key}) : super(key: key);

  @override
  State<GraduationPickerWidget> createState() => _GraduationPickerWidget();
}

class _GraduationPickerWidget extends State<GraduationPickerWidget> {
  GraduationInformationJson graduationInformation = GraduationInformationJson();
  List<String> yearList = [];
  List<Map> divisionList = [];
  List<Map> departmentList = [];
  double width = 0;
  String? _selectedYear;
  Map? _selectedDivision;
  Map? _selectedDepartment;
  final Map<String, String> _presetDepartment = <String, String>{};

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero).then((_) {
      _addSelectTask();
    });
  }

  Future<void> _addSelectTask() async {
    await _getYearList();
    //利用學號預設學年度
    if (graduationInformation.selectYear.isEmpty) {
      graduationInformation.selectYear = LocalStorage.instance.getAccount().substring(0, 3);
    }
    for (String v in yearList) {
      if (v.contains(graduationInformation.selectYear)) {
        _selectedYear = v;
        break;
      }
    }
    await _getDivisionList();
    //利用北科行動助理預設學制與系所
    if (graduationInformation.selectDivision.isEmpty) {
      graduationInformation.selectDivision = _presetDepartment["division"] ?? "";
    }
    for (Map v in divisionList) {
      if (v["name"]?.contains(graduationInformation.selectDivision) ?? false) {
        _selectedDivision = v;
        break;
      }
    }
    await _getDepartmentList();
    if (graduationInformation.selectDepartment.isEmpty) {
      graduationInformation.selectDepartment = _presetDepartment["department"] ?? "";
    }
    for (Map v in departmentList) {
      if (v["name"]?.contains(graduationInformation.selectDepartment) ?? false) {
        _selectedDepartment = v;
        break;
      }
    }
    await _getCreditInfo();
    if (mounted) setState(() {});
  }

  Widget buildText(String title) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        Expanded(
          child: Text(title, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  List<DropdownMenuItem<String>> buildYearList() {
    return yearList
        .map(
          (val) => DropdownMenuItem(
            value: val,
            child: buildText(val),
          ),
        )
        .toList();
  }

  List<DropdownMenuItem<Map>> buildDivisionList() {
    return divisionList
        .map(
          (val) => DropdownMenuItem(
            value: val,
            child: buildText(val["name"]?.toString() ?? ""),
          ),
        )
        .toList();
  }

  List<DropdownMenuItem<Map>> buildDepartmentList() {
    return departmentList
        .map(
          (val) => DropdownMenuItem(
            value: val,
            child: buildText(val["name"]?.toString() ?? ""),
          ),
        )
        .toList();
  }

  Future<void> _getYearList() async {
    TaskFlow taskFlow = TaskFlow();
    var task = CourseYearTask();
    taskFlow.addTask(task);
    if (await taskFlow.start()) {
      yearList = task.result ?? <String>[];
      if (yearList.isNotEmpty) _selectedYear = yearList.first;
    }
    setState(() {});
  }

  Future<void> _getDivisionList() async {
    final selectedYear = _selectedYear;
    if (selectedYear == null || selectedYear.isEmpty) return;
    final parts = selectedYear.split(" ");
    final year = parts.length > 1 ? parts[1] : parts.first;
    final taskFlow = TaskFlow();
    final task = CourseDivisionTask(year);
    taskFlow.addTask(task);
    if (await taskFlow.start()) {
      divisionList = task.result ?? <Map>[];
      _selectedDivision = divisionList.isNotEmpty ? divisionList.first : null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _getDepartmentList() async {
    final selectedDivision = _selectedDivision;
    if (selectedDivision == null) return;
    final rawCode = selectedDivision["code"];
    if (rawCode is! Map) return;
    final code = rawCode.map((key, value) => MapEntry(key.toString(), value.toString()));
    final taskFlow = TaskFlow();
    final task = CourseDepartmentTask(code);
    taskFlow.addTask(task);
    if (await taskFlow.start()) {
      departmentList = task.result ?? <Map>[];
      _selectedDepartment = departmentList.isNotEmpty ? departmentList.first : null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _getCreditInfo() async {
    final selectedDivision = _selectedDivision;
    final selectedDepartment = _selectedDepartment;
    final selectedYear = _selectedYear;
    if (selectedDivision == null || selectedDepartment == null || selectedYear == null) return;
    final rawCode = selectedDivision["code"];
    if (rawCode is! Map) return;
    final code = rawCode.map((key, value) => MapEntry(key.toString(), value.toString()));
    final name = selectedDepartment["name"]?.toString() ?? "";
    if (name.isEmpty) return;
    final taskFlow = TaskFlow();
    final task = CourseCreditInfoTask(code, name);
    taskFlow.addTask(task);
    if (await taskFlow.start()) {
      final result = task.result;
      if (result != null) {
        graduationInformation = result;
        graduationInformation.selectYear = selectedYear;
        graduationInformation.selectDivision = selectedDivision["name"]?.toString() ?? "";
        graduationInformation.selectDepartment = selectedDepartment["name"]?.toString() ?? "";
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    width = MediaQuery.of(context).size.width;
    width = width * 0.8;
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  R.current.graduationSetting,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true, //裡面元素是否要Expanded
                      value: _selectedYear,
                      items: buildYearList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedYear = value;
                          _getDivisionList();
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: DropdownButton<Map>(
                      isExpanded: true,
                      value: _selectedDivision,
                      items: buildDivisionList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedDivision = value;
                          _getDepartmentList();
                        });
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Expanded(
                    child: DropdownButton<Map>(
                      isExpanded: true,
                      value: _selectedDepartment,
                      items: buildDepartmentList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedDepartment = value;
                        });
                        _getCreditInfo();
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    child: Text(R.current.cancel),
                    onPressed: () {
                      _cancel();
                    },
                  ),
                  TextButton(
                    child: Text(R.current.save),
                    onPressed: () {
                      _save();
                    },
                  )
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  void _save() {
    _returnValue();
  }

  void _cancel() {
    graduationInformation = LocalStorage.instance.getGraduationInformation();
    _returnValue();
  }

  void _returnValue() {
    Get.back(result: graduationInformation);
  }
}
