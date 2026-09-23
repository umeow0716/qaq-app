import 'dart:io';
import 'dart:ui' as ui;

import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qaq_app/debug/log/log.dart';
import 'package:qaq_app/src/config/app_config.dart';
import 'package:qaq_app/src/config/app_link.dart';
import 'package:qaq_app/src/connector/ntut_connector.dart';
import 'package:qaq_app/src/file/file_store.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';
import 'package:qaq_app/src/task/ntut/ntut_task.dart';
import 'package:qaq_app/src/task/task_flow.dart';
import 'package:qaq_app/ui/other/msg_dialog.dart';
import 'package:qaq_app/ui/other/my_toast.dart';
import 'package:qaq_app/ui/other/route_utils.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

enum OnListViewPress { setting, fileViewer, logout, feedback, about, login, subSystem }

class OtherPage extends StatefulWidget {
  final PageController pageController;

  const OtherPage(this.pageController, {super.key});

  @override
  State<OtherPage> createState() => _OtherPageState();
}

class _OtherPageState extends State<OtherPage> {
  static const _platform = MethodChannel(AppConfig.methodChannelName);

  final ImagePicker _imagePicker = ImagePicker();
  Future<Uint8List?>? _avatarFuture;
  Uint8List? _lastAvatarBytes;
  bool _isUpdatingAvatar = false;
  final List<Map<String, Object?>> optionList = [
    {
      "icon": EvaIcons.settings2Outline,
      "color": Colors.orange,
      "title": R.current.setting,
      "onPress": OnListViewPress.setting,
    },
    {
      "icon": Icons.computer,
      "color": Colors.lightBlue,
      "title": R.current.informationSystem,
      "onPress": OnListViewPress.subSystem,
    },
    {
      "icon": EvaIcons.downloadOutline,
      "color": Colors.yellow[700],
      "title": R.current.fileViewer,
      "onPress": OnListViewPress.fileViewer,
    },
    if (LocalStorage.instance.getPassword().isNotEmpty)
      {
        "icon": EvaIcons.undoOutline,
        "color": Colors.teal[400],
        "title": R.current.logout,
        "onPress": OnListViewPress.logout,
      },
    if (LocalStorage.instance.getPassword().isEmpty)
      {"icon": EvaIcons.logIn, "color": Colors.teal[400], "title": R.current.login, "onPress": OnListViewPress.login},
    if (Platform.isAndroid)
      {
        "icon": EvaIcons.messageSquareOutline,
        "color": Colors.cyan,
        "title": R.current.feedbackForm,
        "onPress": OnListViewPress.feedback,
      },
    {
      "icon": EvaIcons.infoOutline,
      "color": Colors.lightBlue,
      "title": R.current.about,
      "onPress": OnListViewPress.about,
    },
  ];

  @override
  void initState() {
    super.initState();
    _avatarFuture = _loadAvatar();
    Future.microtask(_recoverLostAvatar);
  }

  Future<Uint8List?> _loadAvatar() async {
    try {
      final taskFlow = TaskFlow();
      final task = NTUTTask("ImageTask");
      task.openLoadingDialog = false;
      taskFlow.addTask(task);
      if (!await taskFlow.start()) return _lastAvatarBytes;

      final bytes = await NTUTConnector.getUserImageBytes();

      ui.Codec? codec;
      ui.FrameInfo? frameInfo;
      try {
        codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
        frameInfo = await codec.getNextFrame();
      } finally {
        frameInfo?.image.dispose();
        codec?.dispose();
      }

      _lastAvatarBytes = bytes;
      return bytes;
    } catch (error, stackTrace) {
      Log.eWithStack('Avatar load failed: $error', stackTrace);
      return _lastAvatarBytes;
    }
  }

  void _reloadAvatar() {
    _avatarFuture = _loadAvatar();
  }

  Future<void> _recoverLostAvatar() async {
    if (!Platform.isAndroid) return;

    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty) return;

      final files = response.files;
      if (files != null && files.isNotEmpty) {
        await _uploadAvatarFile(files.first);
      } else if (response.exception != null) {
        Log.e(response.exception.toString());
      }
    } catch (error, stackTrace) {
      Log.eWithStack(error.toString(), stackTrace);
    }
  }

  void _showAvatarSourceSheet() {
    if (_isUpdatingAvatar) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(R.current.chooseAvatarFromPhotos),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(R.current.takeAvatarPhoto),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickAvatar(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
        preferredCameraDevice: CameraDevice.front,
      );
      if (image == null) return;
      await _uploadAvatarFile(image);
    } catch (error, stackTrace) {
      Log.eWithStack(error.toString(), stackTrace);
      MyToast.show(R.current.avatarUpdateFailed);
    }
  }

  Future<void> _uploadAvatarFile(XFile image) async {
    if (_isUpdatingAvatar) return;
    setState(() => _isUpdatingAvatar = true);

    try {
      final imageBytes = await image.readAsBytes();
      final taskFlow = TaskFlow();
      final loginTask = NTUTTask("AvatarUpload");
      loginTask.openLoadingDialog = false;
      taskFlow.addTask(loginTask);
      if (!await taskFlow.start()) return;

      final newFilename = await NTUTConnector.uploadUserImage(imageBytes);
      LocalStorage.instance.getUserInfo().userPhoto = newFilename;
      await LocalStorage.instance.saveUserData();
      await LocalStorage.instance.cacheManager.emptyCache();

      if (!mounted) return;
      setState(() {
        _reloadAvatar();
      });
      MyToast.show(R.current.avatarUpdated);
    } catch (error, stackTrace) {
      Log.eWithStack(error.toString(), stackTrace);
      MyToast.show(R.current.avatarUpdateFailed);
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvatar = false);
      }
    }
  }

  void _onListViewPress(OnListViewPress value) async {
    switch (value) {
      case OnListViewPress.subSystem:
        RouteUtils.toSubSystemPage(R.current.informationSystem, null);
        break;
      case OnListViewPress.logout:
        MsgDialogParameter parameter = MsgDialogParameter(
          desc: R.current.logoutWarning,
          dialogType: DialogType.warning,
          title: R.current.warning,
          okButtonText: R.current.sure,
          onOkButtonClicked: () {
            Get.back();
            TaskFlow.resetLoginStatus();
            LocalStorage.instance.logout().then((_) => RouteUtils.toLoginScreen());
          },
        );
        MsgDialog(parameter).show();
        break;
      case OnListViewPress.login:
        RouteUtils.toLoginScreen().then((value) {
          if (value == true) widget.pageController.jumpToPage(0);
        });
        break;
      case OnListViewPress.fileViewer:
        FileStore.findLocalPath().then((filePath) {
          RouteUtils.toFileViewerPage(R.current.fileViewer, filePath);
        });
        break;
      case OnListViewPress.feedback:
        final link = await _buildFeedbackUrl();
        await launchUrl(link, mode: LaunchMode.externalApplication);
        break;
      case OnListViewPress.about:
        RouteUtils.toAboutPage();
        break;
      case OnListViewPress.setting:
        RouteUtils.toSettingPage(widget.pageController);
        break;
    }
  }

  Future<Uri> _buildFeedbackUrl() async {
    try {
      final deviceInfo = await _platform.invokeMapMethod<String, dynamic>('get_feedback_device_info');
      final model = deviceInfo?['model']?.toString().trim();
      final androidRelease = deviceInfo?['androidRelease']?.toString().trim();
      if (model != null && model.isNotEmpty && androidRelease != null && androidRelease.isNotEmpty) {
        return AppLink.feedbackFormUrl(deviceModel: model, androidRelease: androidRelease);
      }
    } on PlatformException catch (error, stackTrace) {
      Log.eWithStack(error, stackTrace);
    } on MissingPluginException catch (error, stackTrace) {
      Log.eWithStack(error, stackTrace);
    }
    return AppLink.feedbackFormBaseUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(R.current.titleOther)),
      body: Column(
        children: <Widget>[
          if (LocalStorage.instance.getAccount().isNotEmpty) SizedBox(child: _buildHeader()),
          const SizedBox(height: 16),
          Expanded(
            child: AnimationLimiter(
              child: ListView.builder(
                itemCount: optionList.length,
                itemBuilder: (context, index) => AnimationConfiguration.staggeredList(
                  position: index,
                  duration: const Duration(milliseconds: 375),
                  child: ScaleAnimation(child: _buildSetting(optionList[index])),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final userInfo = LocalStorage.instance.getUserInfo();
    String givenName = userInfo.givenName;
    String userMail = userInfo.userMail;
    final columnItem = <Widget>[];
    final data = MediaQuery.of(context);
    if (givenName.isNotEmpty) {
      columnItem
        ..add(Text(givenName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))
        ..add(const SizedBox(height: 5.0))
        ..add(
          MediaQuery(
            data: data.copyWith(textScaler: TextScaler.noScaling),
            child: Text(userMail, style: const TextStyle(fontSize: 16)),
          ),
        );
    } else {
      givenName = (givenName.isEmpty) ? R.current.pleaseLogin : givenName;
      userMail = (userMail.isEmpty) ? "" : userMail;
    }
    return Container(
      padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0, bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: InkWell(
              onTap: _showAvatarSourceSheet,
              child: FutureBuilder<Uint8List?>(
                future: _avatarFuture,
                builder: (context, snapshot) {
                  if (_isUpdatingAvatar) {
                    return SpinKitRotatingCircle(color: Theme.of(context).colorScheme.secondary);
                  }
                  final bytes = snapshot.data ?? _lastAvatarBytes;
                  if (bytes != null) {
                    return ClipOval(
                      child: Image.memory(
                        bytes,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) {
                          if (stackTrace != null) {
                            Log.eWithStack('Avatar decode failed: $error', stackTrace);
                          } else {
                            Log.e('Avatar decode failed: $error');
                          }
                          return const Icon(Icons.person_outline);
                        },
                      ),
                    );
                  }
                  if (snapshot.connectionState != ConnectionState.done) {
                    return CircularProgressIndicator(color: Theme.of(context).colorScheme.secondary);
                  }
                  return const Icon(Icons.person_outline);
                },
              ),
            ),
          ),
          const SizedBox(width: 16.0),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: columnItem,
          ),
        ],
      ),
    );
  }

  Widget _buildSetting(Map<String, Object?> data) {
    return InkWell(
      onTap: () {
        final action = data['onPress'];
        if (action is OnListViewPress) _onListViewPress(action);
      },
      child: Container(
        padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0, bottom: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(data['icon'] as IconData, color: data['color'] as Color?),
            const SizedBox(width: 20.0),
            Text(data['title']?.toString() ?? '', style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
