import 'dart:async';
import 'dart:html' as html;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:js/js.dart';
import 'package:video_js/src/web/json.dart';
import 'package:video_js/src/web/until.dart';
import 'package:video_js/src/web/video_js.dart';
import 'package:video_js/video_js.dart';

import 'video_js_player.dart';

const videoJsWrapperId = 'videoJsWrapper';

class VideoJsController {
  final String playerId;
  final VideoJsOptions? videoJsOptions;
  late String textureId;
  late html.DivElement playerWrapperElement;
  late Player player;
  bool initialized = false;

  VideoJsController(this.playerId, {this.videoJsOptions}) {
    textureId = _generateRandomString(7);

    playerWrapperElement = html.DivElement()
      ..id = videoJsWrapperId
      ..style.width = '100%'
      ..style.height = '100%'
      ..children = [
        html.VideoElement()
          ..id = playerId
          ..className = 'video-js vjs-default-skin'
      ];

    playerWrapperElement.addEventListener(
      'contextmenu',
      (event) => event.preventDefault(),
      false,
    );

    // ignore: undefined_prefixed_name
    ui.platformViewRegistry
        .registerViewFactory(textureId, (int id) => playerWrapperElement);
  }

  Future<void> init() async {
    try {
      if (initialized) {
        return;
      }
      player = await initPlayer();
      player.on(
        'ended',
        allowInterop(([arg1, arg2]) {
          VideoJsResults().addEvent(
            VideoEvent(key: playerId, eventType: VideoEventType.completed),
          );
        }),
      );
      player.on(
        'play',
        allowInterop(([arg1, arg2]) {
          VideoJsResults().addEvent(
            VideoEvent(key: playerId, eventType: VideoEventType.play),
          );
        }),
      );
      player.on(
        'pause',
        allowInterop(([arg1, arg2]) {
          VideoJsResults().addEvent(
            VideoEvent(key: playerId, eventType: VideoEventType.pause),
          );
        }),
      );
      player.on(
        'loadstart',
        allowInterop(([arg1, arg2]) {
          VideoJsResults().addEvent(
            VideoEvent(
              key: playerId,
              eventType: VideoEventType.bufferingStart,
            ),
          );
        }),
      );
      player.on(
        'progress',
        allowInterop(([arg1, arg2]) {
          final buffered = player.buffered();
          final duration = parseDuration(player.duration());
          final bufferedRanges = Iterable<int>.generate(buffered.length)
              .toList()
              .map(
                (e) => DurationRange(
                  parseDuration(buffered.start(e)),
                  parseDuration(buffered.end(e)),
                ),
              )
              .toList();
          if (bufferedRanges.isNotEmpty &&
              bufferedRanges.last.end == duration) {
            VideoJsResults().addEvent(
              VideoEvent(
                key: playerId,
                eventType: VideoEventType.bufferingEnd,
              ),
            );
          } else {
            VideoJsResults().addEvent(
              VideoEvent(
                key: playerId,
                eventType: VideoEventType.bufferingUpdate,
                buffered: bufferedRanges,
              ),
            );
          }
        }),
      );
      player.eme();
      initialized = true;
    } catch (e) {
      print(e);
    }
  }

  /// To generate random string for HtmlElementView ID
  String _generateRandomString(int len) {
    final r = Random();
    const chars =
        'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    return List.generate(len, (index) => chars[r.nextInt(chars.length)]).join();
  }

  Future<Player> initPlayer() {
    final completer = Completer<Player>();

    final player = videojs(
      playerId,
      PlayerOptions(
        autoplay: true,
        autoSetup: true,
        fluid: true,
        aspectRatio: '16:9',
        children: ['MediaLoader', 'LiveTracker', 'ResizeManager'],
        html5: Html5Options(
          vhs: VhsOptions(limitRenditionByPlayerDimensions: false),
        ),
      ),
    );
    player.ready(
      allowInterop(() {
        completer.complete(player);
      }),
    );
    return completer.future;
  }

  /// to set video source by type
  /// [type] can be video/mp4, video/webm, application/x-mpegURL (for hls videos), ...
  Future<void> setSRC(
    String src, {
    required String type,
    Map<String, dynamic>? keySystems,
    Map<String, String>? emeHeaders,
  }) async {
    final completer = Completer<void>();
    player.src(
      Source(
        src: src,
        type: type,
        keySystems: keySystems,
        emeHeaders: emeHeaders,
      ),
    );
    player.one(
      'loadedmetadata',
      allowInterop(([arg1, arg2]) {
        VideoJsResults().addEvent(
          VideoEvent(
            eventType: VideoEventType.initialized,
            key: playerId,
            duration: parseDuration(player.duration()),
            size: ui.Size(
              player.videoWidth().toDouble(),
              player.videoHeight().toDouble(),
            ),
          ),
        );
        completer.complete();
      }),
    );
    return completer.future;
  }

  /// set volume to video player
  Future<void> setVolume(double volume) async {
    player.volume(volume);
  }

  /// play video
  play() async {
    if (player.paused()) {
      await player.play();
    }
  }

  /// pause video
  pause() async {
    if (!player.paused()) {
      player.pause();
    }
  }

  /// To get video's current playing time in seconds
  Future<Duration> currentTime() async {
    return parseDuration(player.currentTime());
  }

  /// Set video
  setCurrentTime(Duration value) async {
    return player.currentTime(value.inSeconds);
  }

  Future<void> setAudioTrack(int index, String id) async {
    final audioTrackList = player.audioTracks();

    if (audioTrackList.length <= 0) {
      return;
    }
    if (index < 0 || index > audioTrackList.length - 1) {
      return;
    }
    audioTrackList.getTrackById(id).enabled = true;
  }

  Future<QualityLevels> getQualityLevels() async {
    return player.qualityLevels();
  }

  Future<void> setDefaultTrack() async {
    final qualityLevels = player.qualityLevels();
    for (int index = 0; index < qualityLevels.length; ++index) {
      final quality = qualityLevels.levels_[index];
      quality.enabled = true;
    }
  }

  Future<void> setQualityLevel(int bitrate, int? width, int? height) async {
    final qualityLevels = player.qualityLevels();
    for (int index = 0; index < qualityLevels.length; ++index) {
      final quality = qualityLevels.levels_[index];
      if (quality.bitrate == bitrate &&
          (width != null ? quality.width == width : true) &&
          (height != null ? quality.height == height : true)) {
        quality.enabled = true;
      } else {
        quality.enabled = false;
      }
    }
  }

  dispose() async {
    player.dispose();
  }
}
