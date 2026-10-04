class DesktopPortalShortcut {
  const DesktopPortalShortcut({
    required this.zhLabel,
    required this.enLabel,
    required this.apOu,
  });

  final String zhLabel;
  final String enLabel;
  final String apOu;

  String label({required bool english}) => english ? enLabel : zhLabel;

  Uri get uri => Uri.https(
    'nportal.ntut.edu.tw',
    '/ssoIndex.do',
    <String, String>{'apOu': apOu},
  );
}

const desktopPortalShortcuts = <DesktopPortalShortcut>[
  DesktopPortalShortcut(
    zhLabel: '課程系統',
    enLabel: 'Curriculum System',
    apOu: 'aa_0010-oauth',
  ),
  DesktopPortalShortcut(
    zhLabel: '北科 i 學園',
    enLabel: 'ISchool Plus',
    apOu: 'ischool_plus_oauth',
  ),
  DesktopPortalShortcut(
    zhLabel: '學業成績查詢專區',
    enLabel: 'Students Grades Query System',
    apOu: 'aa_003_LB_oauth',
  ),
  DesktopPortalShortcut(
    zhLabel: '期末網路教學評量系統',
    enLabel: 'Course Evaluation System',
    apOu: 'aa_009_oauth',
  ),
  DesktopPortalShortcut(
    zhLabel: '學生查詢專區',
    enLabel: 'Students Query System',
    apOu: 'sa_003_oauth',
  ),
  DesktopPortalShortcut(
    zhLabel: '學生請假系統',
    enLabel: 'Student Ask for Leave System',
    apOu: 'sa_010_oauth',
  ),
  DesktopPortalShortcut(
    zhLabel: '網路郵局 WebMail',
    enLabel: 'WebMail',
    apOu: 'zimbrasso_oauth',
  ),
];
