import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screen_wake/flutter_screen_wake.dart';
import 'package:http/http.dart' as http;
import 'package:lecle_yoyo_player/src/enums/video_format.dart';
import 'package:lecle_yoyo_player/src/model/models.dart';
import 'package:lecle_yoyo_player/src/responses/regex_response.dart';
import 'package:lecle_yoyo_player/src/utils/utils.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class YoYoPlayer extends StatefulWidget {
  const YoYoPlayer({
    required this.url,
    required this.loading,
    super.key,
    this.aspectRatio = 9 / 16,
    this.autoPlayVideoAfterInit = true,
    this.allowCacheFile = false,
    this.formatResolver,
    this.onVideoInitCompleted,
  });

  final String url;
  final Widget loading;
  final double aspectRatio;
  final void Function(VideoPlayerController controller)? onVideoInitCompleted;
  final bool autoPlayVideoAfterInit;
  final bool allowCacheFile;
  final VideoFormat Function(Uri uri)? formatResolver;

  @override
  State<YoYoPlayer> createState() => _YoYoPlayerState();
}

class _YoYoPlayerState extends State<YoYoPlayer>
    with SingleTickerProviderStateMixin {
  YoyoVideoFormat playType = YoyoVideoFormat.other;
  late VideoPlayerController controller;
  List<M3U8Data> yoyo = [];
  List<AudioModel> audioList = [];
  String? m3u8Content;
  bool? isOffline;
  Duration? lastPlayedPos;

  @override
  void initState() {
    super.initState();
    urlCheck(widget.url);

    FlutterScreenWake.keepOn(true);
  }

  @override
  void dispose() {
    m3u8Clean();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: switch (controller.value.isInitialized) {
          true => Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          false => widget.loading
        },
      );

  Future<void> urlCheck(String url) async {
    final netRegex = RegExp(RegexResponse.regexHTTP);
    final isNetwork = netRegex.hasMatch(url);
    final uri = Uri.parse(url);

    setStateIfMounted(() => isOffline = !isNetwork);

    if (isNetwork) return _handleNetworkVideo(uri, url);
    return videoControlSetup(url);
  }

  void _handleNetworkVideo(Uri uri, String url) {
    final playType = switch (widget.formatResolver) {
      final YoyoVideoFormat Function(Uri url) resolver => resolver(uri),
      _ => switch (uri.pathSegments.last) {
          final val when val.endsWith('mkv') => YoyoVideoFormat.mkv,
          final val when val.endsWith('mp4') => YoyoVideoFormat.mp4,
          final val when val.endsWith('webm') => YoyoVideoFormat.webm,
          final val when val.endsWith('m3u8') => YoyoVideoFormat.m3u8,
          _ => YoyoVideoFormat.other
        },
    };

    setStateIfMounted(() => this.playType = playType);
    return switch (playType) {
      YoyoVideoFormat.mkv => _handleMKV(url),
      YoyoVideoFormat.mp4 => _handleMP4(url),
      YoyoVideoFormat.webm => _handleWEBM(url),
      YoyoVideoFormat.m3u8 => _handleHLS(url),
      _ => _handleFallback(url),
    };
  }

  void _handleFallback(String url) {
    videoControlSetup(url);
    getM3U8(url);
  }

  void _handleHLS(String url) {
    videoControlSetup(url);
    getM3U8(url);
  }

  void _handleWEBM(String url) {
    videoControlSetup(url);
    if (!widget.allowCacheFile) return;
    FileUtils.cacheFileToLocalStorage(url, fileExtension: 'webm');
  }

  void _handleMP4(String url) {
    videoControlSetup(url);
    if (!widget.allowCacheFile) return;
    FileUtils.cacheFileToLocalStorage(url, fileExtension: 'mp4');
  }

  void _handleMKV(String url) {
    videoControlSetup(url);
    if (!widget.allowCacheFile) return;
    FileUtils.cacheFileToLocalStorage(url, fileExtension: 'mkv');
  }

  void getM3U8(String videoUrl) {
    if (yoyo.isNotEmpty) m3u8Clean().ignore();
    m3u8Video(videoUrl).ignore();
  }

  Future<M3U8s?> m3u8Video(String? videoUrl) async {
    yoyo.add(M3U8Data(dataQuality: 'Auto', dataURL: videoUrl));
    final RegExp regExp = RegExp(
      RegexResponse.regexM3U8Resolution,
      caseSensitive: false,
      multiLine: true,
    );

    if (m3u8Content != null) setStateIfMounted(() => m3u8Content = null);
    if (m3u8Content == null && videoUrl != null) {
      final http.Response response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode != 200) return null;
      m3u8Content = utf8.decode(response.bodyBytes);

      final List<File> cachedFiles = [];
      int index = 0;

      final List<RegExpMatch> matches =
          regExp.allMatches(m3u8Content ?? '').toList();

      for (final RegExpMatch regExpMatch in matches) {
        final String quality = regExpMatch.group(1).toString();
        final String sourceURL = regExpMatch.group(3).toString();
        final netRegex = RegExp(RegexResponse.regexHTTP);
        final netRegex2 = RegExp(RegexResponse.regexURL);
        final isNetwork = netRegex.hasMatch(sourceURL);
        final match = netRegex2.firstMatch(videoUrl);
        String url;
        if (isNetwork) {
          url = sourceURL;
        } else {
          final dataURL = match?.group(0);
          url = '$dataURL$sourceURL';
        }
        for (final RegExpMatch regExpMatch2 in matches) {
          final String audioURL = regExpMatch2.group(1).toString();
          final isNetwork = netRegex.hasMatch(audioURL);
          final match = netRegex2.firstMatch(videoUrl);
          String auURL = audioURL;

          if (!isNetwork) {
            final auDataURL = match!.group(0);
            auURL = '$auDataURL$audioURL';
          }

          audioList.add(AudioModel(url: auURL));
        }

        String audio = '';
        if (audioList.isNotEmpty) {
          audio =
              '''#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-medium",NAME="audio",AUTOSELECT=YES,DEFAULT=YES,CHANNELS="2",
                  URI="${audioList.last.url}"\n''';
        } else {
          audio = '';
        }

        if (widget.allowCacheFile) {
          try {
            final file = await FileUtils.cacheFileUsingWriteAsString(
              contents:
                  '''#EXTM3U\n#EXT-X-INDEPENDENT-SEGMENTS\n$audio#EXT-X-STREAM-INF:CLOSED-CAPTIONS=NONE,BANDWIDTH=1469712,
                  RESOLUTION=$quality,FRAME-RATE=30.000\n$url''',
              quality: quality,
              videoUrl: url,
            );
            if (file != null) cachedFiles.add(file);
            if (index < matches.length) index++;
          } catch (e) {
            //
          }
        }
        yoyo.add(M3U8Data(dataQuality: quality, dataURL: url));
      }
      return M3U8s(m3u8s: yoyo);
    }
    return null;
  }

  void videoControlSetup(String url) {
    videoInit(url).then((value) {
      controller.addListener(listener);
      if (widget.autoPlayVideoAfterInit) controller.play();
      widget.onVideoInitCompleted?.call(controller);
    });
  }

  Future<void> listener() async {
    final enabled = await WakelockPlus.enabled;
    final isPlaying =
        controller.value.isInitialized && controller.value.isPlaying;

    if (!isPlaying && enabled) {
      await WakelockPlus.disable();
      return setStateIfMounted();
    }
    if (enabled) return;

    await WakelockPlus.enable();
    return setStateIfMounted();
  }

  Future<void> videoInit(String? url) {
    if (isOffline ?? false) return _intiFallback(url);
    return switch (playType) {
      YoyoVideoFormat.mkv => _initMKV(url),
      YoyoVideoFormat.mp4 => _initOther(url),
      YoyoVideoFormat.webm => _initOther(url),
      YoyoVideoFormat.m3u8 => _initHLS(url),
      _ => _intiFallback(url),
    };
  }

  Future<void> _intiFallback(String? url) async {
    controller = VideoPlayerController.file(File(url!));
    await controller.initialize().then((value) {
      seekToLastPlayingPosition();
    }).catchError((e) {});
  }

  Future<void> _initHLS(String? url) async {
    controller = VideoPlayerController.networkUrl(
      Uri.parse(url!),
      formatHint: VideoFormat.hls,
    );
    await controller.initialize().then((_) {
      seekToLastPlayingPosition();
    }).catchError((e) {});
  }

  Future<void> _initMKV(String? url) async {
    controller = VideoPlayerController.networkUrl(
      Uri.parse(url!),
      formatHint: VideoFormat.dash,
    );
    await controller.initialize().then((value) => seekToLastPlayingPosition);
  }

  Future<void> _initOther(String? url) async {
    controller = VideoPlayerController.networkUrl(
      Uri.parse(url!),
      formatHint: VideoFormat.other,
    );
    await controller.initialize().then((value) => seekToLastPlayingPosition);
  }

  Future<void> m3u8Clean() async {
    for (int i = 2; i < yoyo.length; i++) {
      try {
        final file = await FileUtils.readFileFromPath(
          videoUrl: yoyo[i].dataURL ?? '',
          quality: yoyo[i].dataQuality ?? '',
        );
        final exists = file?.existsSync() ?? false;
        if (exists) await file?.delete();
      } catch (e) {}
    }
    audioList.clear();
    yoyo.clear();
  }

  void seekToLastPlayingPosition() {
    if (lastPlayedPos == null) return;
    controller.seekTo(lastPlayedPos!);
    widget.onVideoInitCompleted?.call(controller);
    lastPlayedPos = null;
  }

  void setStateIfMounted([VoidCallback? f]) => switch (mounted) {
        true => setState(f ?? () {}),
        false => null,
      };
}
