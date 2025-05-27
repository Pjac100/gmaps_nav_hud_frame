import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:simple_frame_app/text_utils.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:frame_msg/tx/sprite.dart';
import 'package:frame_msg/tx/plain_text.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {

  String _prevText = '';
  Uint8List _prevIcon = Uint8List(0);
  ServiceNotificationEvent? _lastEvent;
  StreamSubscription<ServiceNotificationEvent>? notifSubs;
  final TextStyle _style = const TextStyle(color: Colors.white, fontSize: 12);
  final TextStyle _smallStyle = const TextStyle(color: Colors.white, fontSize: 8);


  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    tryScanAndConnectAndStart(andRun: true);
  }

  String? extractSubTextFromString(String bundleString) {
    // This regex looks for "android.subText=" followed by any characters
    // that are not a comma or a closing curly brace.
    final regex = RegExp(r'android\.subText=([^,}]+)');
    final match = regex.firstMatch(bundleString);
    var subText = match?.group(1); // group(1) is the captured value

    // subText may be the string "null" during the "Starting navigation" notification
    if (subText != null && subText != "null") {
      return subText.trim(); // Return the trimmed subText if found
    }
    else {
      return null;
    }
  }

  String _formatTimestampToLocalDateString(int? timestampMillis) {
    if (timestampMillis == null) {
      return "N/A"; // Or an empty string, or however you'd like to handle null
    }
    // Create a DateTime object from milliseconds since epoch (this is in UTC)
    final DateTime dateTimeUtc = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
    // Convert to the local timezone of the device
    final DateTime localDateTime = dateTimeUtc.toLocal();
    // DateTime.toString() produces a format like "YYYY-MM-DD HH:MM:SS.ffffff"
    // We can remove the microseconds part for a cleaner "any old date string".
    String isoString = localDateTime.toString();
    int dotIndex = isoString.lastIndexOf('.');
    if (dotIndex != -1) {
      return isoString.substring(0, dotIndex); // Returns "YYYY-MM-DD HH:MM:SS"
    }
    return isoString; // Fallback, though toString() usually includes microseconds or milliseconds
  }

  /// Extract the details from the notification and send to Frame
  void handleNotification(ServiceNotificationEvent event) async {
    _log.fine('onData: $event');

    // filter notifications for Maps
    if (event.packageName != null && event.packageName == "com.google.android.apps.maps") {
      setState(() {
        _lastEvent = event;
      });

      try {
        // send text to Frame
        String text = '${event.title}\n${event.content ?? ""}\n${extractSubTextFromString(event.userId ?? '') ?? ''}';
        _log.finest('Text: $text');
        if (text != _prevText) {
          List<String> wrappedText = TextUtils.wrapText(text, 500, 4);
          await frame?.sendMessage(0x0a, TxPlainText(text: wrappedText.join("\n")).pack());
          _prevText = text;
        }

        if (event.largeIcon != null && event.largeIcon!.isNotEmpty) {
          Uint8List iconBytes = event.largeIcon!;
          _log.finest('Icon bytes: ${iconBytes.length}: $iconBytes');

          if (!listEquals(iconBytes, _prevIcon)) {
            _prevIcon = iconBytes;
            // TODO if the maps icons are all 2-color bitmaps even though they're RGB(A?) bitmaps,
            // maybe we can pack them and send as an indexed file more easily than having to do quantize()? Or using Image() at all.
            final img.Image? image = img.decodeImage(iconBytes);

            // Ensure the image is loaded correctly
            if (image != null) {
              _log.fine('Image: ${image.width}x${image.height}, ${image.format}, ${image.hasAlpha}, ${image.hasPalette}, ${image.length}');
              _log.finest('Image bytes: ${image.toUint8List()}');

              // quantize the image for pack/send/display to frame
              final qImage = img.quantize(image, numberOfColors: 4, method: img.QuantizeMethod.binary, dither: img.DitherKernel.none, ditherSerpentine: false);
              Uint8List qImageBytes = qImage.toUint8List();
              _log.fine('QuantizedImage: ${qImage.width}x${qImage.height}, ${qImage.format}, ${qImage.hasAlpha}, ${qImage.hasPalette}, ${qImage.palette!.toUint8List()}, ${qImage.length}');
              _log.finest('QuantizedImage bytes: $qImageBytes');

              // send image message (header and image data) to Frame
              await frame?.sendMessage(0x0d, TxSprite(
                width: qImage.width,
                height: qImage.height,
                numColors: qImage.palette!.lengthInBytes ~/ 3,
                paletteData: qImage.palette!.toUint8List(),
                pixelData: qImageBytes
              ).pack());
            }
          }
        }
      }
      catch (e) {
        _log.severe('Error processing notification: $e');
      }
    }
    else {
      _log.info('Ignoring notification from package: ${event.packageName}');
    }
  }

  @override
  Future<void> run() async {
    setState(() {
      currentState = ApplicationState.running;
    });

    final bool alreadyGranted = await NotificationListenerService.isPermissionGranted();

    if (!alreadyGranted) {
      _log.warning("Notification permission not granted. Please enable it in the app settings.");

      final bool status = await NotificationListenerService.requestPermission();

      if (!status) {
        _log.warning("Notification permission request failed. Exiting.");
        setState(() {
          currentState = ApplicationState.ready;
        });
        return;
      }
      else {
        _log.info("Notification permission granted, continuing.");
      }
    }
    else {
      _log.info("Notification permission already granted.");
    }

    _log.info("start listening for notifications");

    try {
      notifSubs = NotificationListenerService.notificationsStream.listen(handleNotification);
    } on Exception catch (exception) {
      _log.warning("Error starting notification stream: ${exception.toString()}");
    }
  }

  @override
  Future<void> cancel() async {
    _log.info("stop listening");

    setState(() {
      currentState = ApplicationState.canceling;
    });

    notifSubs?.cancel();

    setState(() {
      _prevText = '';
      _prevIcon = Uint8List(0);
      _lastEvent = null;
      currentState = ApplicationState.ready;
    });

    // TODO remove content from Frame display?
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Navigation HUD',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Frame Navigation HUD'),
          actions: [getBatteryWidget()]
        ),
        body: _lastEvent != null ? Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_lastEvent!.title ?? "", style: _style, textAlign: TextAlign.left,),
                  Text(_lastEvent!.content ?? "", style: _style),
                  Text(extractSubTextFromString(_lastEvent!.userId ?? '') ?? '', style: _style),
                  // phone only - last notification timestamp
                  Text(_formatTimestampToLocalDateString(_lastEvent!.postTime), style: _smallStyle),
                ]
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if (_lastEvent!.largeIcon != null && _lastEvent!.largeIcon!.isNotEmpty)
                  Image.memory(_lastEvent!.largeIcon!),
              ],
            )
          ],
        ) : null,
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.navigation), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      )
    );
  }
}