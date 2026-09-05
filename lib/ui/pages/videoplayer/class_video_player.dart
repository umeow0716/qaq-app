import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/connector/core/connector.dart';
import 'package:flutter_app/src/connector/core/connector_parameter.dart';
import 'package:flutter_app/src/file/file_download.dart';
import 'package:flutter_app/src/model/coursetable/course_table_json.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/src/store/local_storage.dart';
import 'package:flutter_app/src/util/language_util.dart';
import 'package:flutter_app/src/util/mx_player_util.dart';
import 'package:flutter_app/ui/other/my_toast.dart';
import 'package:flutter_app/ui/other/route_utils.dart';
import 'package:get/get.dart';
import 'package:html/parser.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';

class ClassVideoPlayer extends StatefulWidget {
  const ClassVideoPlayer(this.videoUrl, this.courseInfo, this.name, {super.key});

  final String videoUrl;
  final CourseInfoJson courseInfo;
  final String name;

  @override
  State<ClassVideoPlayer> createState() => _VideoPlayer();
}

@immutable
class _VideoInfo {
  const _VideoInfo(this.name, this.url);

  final String name;
  final String url;
}

class _VideoPlayer extends State<ClassVideoPlayer> {
  bool _isLoading = true;
  final _videoNames = <_VideoInfo>[];
  VideoPlayerController? _playerController;
  ChewieController? _chewieController;
  _VideoInfo? _selectedVideoInfo;

  @override
  void initState() {
    super.initState();
    parseVideo();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _playerController?.dispose();
    _chewieController?.dispose();

    super.dispose();
  }

  void parseVideo() async {
    _isLoading = true;

    final parameter = ConnectorParameter(widget.videoUrl);
    final result = await Connector.getDataByGet(parameter);
    final tagNode = parse(result);
    final node = tagNode.getElementById("videoplayer");

    if (node == null) {
      MyToast.show(R.current.unknownError);
      Get.back();
      return;
    }

    for (final child in node.children) {
      if (child.children.first.localName == 'source') {
        try {
          final url = child.children.first.attributes['src'];
          if (url == null) {
            continue;
          }

          final info = _VideoInfo(child.id, url);
          _videoNames.add(info);
        } on Exception catch (e, stackTrace) {
          Log.eWithStack(e, stackTrace);
          continue;
        }
      }
    }

    await _buildDialog();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    setState(() => _isLoading = false);
  }

  String getVideoUrl(String path) => "https://istream.ntut.edu.tw/videoplayer/$path";

  Future<void> _buildDialog() async {
    final urlStr = await Get.dialog<String>(
      AlertDialog(
        content: SizedBox(
          width: double.minPositive,
          child: ListView.builder(
            itemCount: _videoNames.length,
            shrinkWrap: true,
            itemBuilder: (context, index) => TextButton(
              child: Text(_videoNames[index].name),
              onPressed: () {
                final url = getVideoUrl(_videoNames[index].url);
                _selectedVideoInfo = _videoNames[index];
                Get.back<String>(result: url);
              },
            ),
          ),
        ),
      ),
      barrierDismissible: true,
    );

    if (urlStr == null) {
      Get.back();
      return;
    }

    bool externalPlayerHasLaunched = false;

    final selectedVideoInfo = _selectedVideoInfo;
    if (selectedVideoInfo == null) {
      Get.back();
      return;
    }

    if (LocalStorage.instance.getOtherSetting().useExternalVideoPlayer) {
      final name = "${widget.name}_${selectedVideoInfo.name}.mp4";
      externalPlayerHasLaunched = await MXPlayerUtil.launch(url: urlStr, name: name);
    }

    final url = Uri.tryParse(urlStr);

    if (!externalPlayerHasLaunched && url != null) {
      await initController(url);
    } else {
      Get.back();
    }
  }

  Future<void> initController(Uri url) async {
    final headers = await Connector.getLoginHeaders(url.toString()) ?? {};
    final playerController = VideoPlayerController.networkUrl(
      url,
      httpHeaders: headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _playerController = playerController;

    playerController.addListener(() => setState(() {}));
    playerController.setLooping(true);

    await playerController.initialize();

    _chewieController = ChewieController(videoPlayerController: playerController, autoPlay: true, autoInitialize: true);
  }

  @override
  Widget build(BuildContext context) {
    final chewieController = _chewieController;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Get.back()),
        title: Text(R.current.classVideo),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: () {
                final url = _playerController?.dataSource;
                if (url == null) {
                  return;
                }

                final selectedVideoInfo = _selectedVideoInfo;
                if (selectedVideoInfo == null) {
                  return;
                }

                final courseName = widget.courseInfo.main.course.name;
                final saveName = "${widget.name}_${selectedVideoInfo.name}.mp4";
                final subDir = (LanguageUtil.getLangIndex() == LangEnum.zh) ? "上課錄影" : "video";
                final dirName = path.join(courseName, subDir);

                FileDownload.download(url, dirName, saveName);
              },
            ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final dataSource = _playerController?.dataSource;

                if (dataSource == null) {
                  return;
                }

                await RouteUtils.toWebViewPage(initialUrl: Uri.parse(dataSource));
              },
            ),
        ],
      ),
      body: SafeArea(
        child: (!_isLoading && chewieController != null)
            ? Chewie(controller: chewieController)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
