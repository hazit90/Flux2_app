import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class DownloadManager {
  DownloadManager({List<String>? baseUrls})
    : _baseUrls = baseUrls ?? _defaultBaseUrls;

  static const List<String> requiredFiles = [
    'text_encoder/config.json',
    'text_encoder/generation_config.json',
    'text_encoder/model.safetensors.index.json',
    'text_encoder/model-00001-of-00002.safetensors',
    'text_encoder/model-00002-of-00002.safetensors',
    'tokenizer/added_tokens.json',
    'tokenizer/chat_template.jinja',
    'tokenizer/merges.txt',
    'tokenizer/special_tokens_map.json',
    'tokenizer/tokenizer.json',
    'tokenizer/tokenizer_config.json',
    'tokenizer/vocab.json',
    'transformer/config.json',
    'transformer/diffusion_pytorch_model.safetensors',
    'vae/config.json',
    'vae/diffusion_pytorch_model.safetensors',
  ];

  static const List<String> _defaultBaseUrls = [
    'http://localhost:8000',
    'http://localmodels.local:8000',
  ];

  final List<String> _baseUrls;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Completer<void>? _downloadCompleter;
  bool _isRunning = false;

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  Future<void> downloadFiles({
    required String modelDir,
    required List<String> requiredFiles,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    _downloadCompleter = Completer<void>();

    _receivePort = ReceivePort();
    _receivePort!.listen(_handleMessage, onDone: _cleanupIsolate);

    _isolate = await Isolate.spawn(_downloadIsolateEntry, {
      'sendPort': _receivePort!.sendPort,
      'baseUrls': _baseUrls,
    });

    await _waitForSendPort();

    _sendPort?.send({
      'type': 'start',
      'modelDir': modelDir,
      'requiredFiles': requiredFiles,
    });

    return _downloadCompleter!.future;
  }

  void cancel() {
    _sendPort?.send({'type': 'cancel'});
  }

  void dispose() {
    cancel();
    _eventController.close();
    _cleanupIsolate();
  }

  Future<void> _waitForSendPort() async {
    if (_sendPort != null) return;
    final completer = Completer<void>();

    late StreamSubscription subscription;
    subscription = _eventController.stream.listen((event) {
      if (event['type'] == 'ready') {
        _sendPort = event['sendPort'] as SendPort?;
        subscription.cancel();
        completer.complete();
      }
    });

    return completer.future;
  }

  void _handleMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      final type = message['type'] as String?;
      if (type == 'ready') {
        _sendPort = message['sendPort'] as SendPort?;
      }
      if (type == 'done') {
        _downloadCompleter?.complete();
        _downloadCompleter = null;
        _cleanupIsolate();
        _isRunning = false;
      } else if (type == 'error') {
        final error = message['message'] ?? 'Download failed';
        _downloadCompleter?.completeError(error);
        _downloadCompleter = null;
        _cleanupIsolate();
        _isRunning = false;
      } else if (type == 'cancelled') {
        _downloadCompleter?.complete();
        _downloadCompleter = null;
        _cleanupIsolate();
        _isRunning = false;
      }

      _eventController.add(message);
    }
  }

  void _cleanupIsolate() {
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

void _downloadIsolateEntry(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final baseUrls = (args['baseUrls'] as List<dynamic>).cast<String>().toList();

  final commandPort = ReceivePort();
  sendPort.send({'type': 'ready', 'sendPort': commandPort.sendPort});

  final cancelSignal = _CancelSignal();

  commandPort.listen((message) async {
    if (message is! Map<String, dynamic>) return;
    final type = message['type'] as String?;
    if (type == 'cancel') {
      cancelSignal.cancel();
      return;
    }
    if (type != 'start') return;

    final modelDir = message['modelDir'] as String;
    final requiredFiles = (message['requiredFiles'] as List<dynamic>)
        .cast<String>();

    try {
      await _runDownloadQueue(
        sendPort: sendPort,
        baseUrls: baseUrls,
        modelDir: modelDir,
        requiredFiles: requiredFiles,
        cancelSignal: cancelSignal,
      );
      if (cancelSignal.cancelled) {
        sendPort.send({'type': 'cancelled'});
      } else {
        sendPort.send({'type': 'done'});
      }
    } catch (error) {
      sendPort.send({'type': 'error', 'message': error.toString()});
    }
  });
}

Future<void> _runDownloadQueue({
  required SendPort sendPort,
  required List<String> baseUrls,
  required String modelDir,
  required List<String> requiredFiles,
  required _CancelSignal cancelSignal,
}) async {
  final queueItems = <Map<String, dynamic>>[];
  for (final relativePath in requiredFiles) {
    final filePath = p.join(modelDir, relativePath);
    final exists = File(filePath).existsSync();
    queueItems.add({
      'path': relativePath,
      'status': exists ? 'completed' : 'pending',
      'progress': exists ? 1.0 : 0.0,
    });
  }

  sendPort.send({'type': 'queue', 'items': queueItems});

  for (final item in queueItems) {
    if (cancelSignal.cancelled) return;
    final status = item['status'] as String;
    if (status == 'completed') continue;

    final relativePath = item['path'] as String;
    sendPort.send({
      'type': 'status',
      'path': relativePath,
      'status': 'downloading',
    });

    await _downloadSingleFile(
      sendPort: sendPort,
      baseUrls: baseUrls,
      modelDir: modelDir,
      relativePath: relativePath,
      cancelSignal: cancelSignal,
    );

    if (cancelSignal.cancelled) return;
    sendPort.send({
      'type': 'status',
      'path': relativePath,
      'status': 'completed',
    });
  }
}

Future<void> _downloadSingleFile({
  required SendPort sendPort,
  required List<String> baseUrls,
  required String modelDir,
  required String relativePath,
  required _CancelSignal cancelSignal,
}) async {
  final client = http.Client();
  try {
    final targetPath = p.join(modelDir, relativePath);
    final tempPath = '$targetPath.partial';
    final targetFile = File(targetPath);
    final tempFile = File(tempPath);

    if (targetFile.existsSync()) {
      return;
    }

    await Directory(p.dirname(targetPath)).create(recursive: true);

    http.StreamedResponse? response;
    Uri? chosenUri;

    for (final baseUrl in baseUrls) {
      if (cancelSignal.cancelled) return;
      try {
        final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
        final uri = Uri.parse(normalizedBase).resolve(relativePath);
        final request = http.Request('GET', uri);
        response = await client.send(request);
        if (response.statusCode == 200) {
          chosenUri = uri;
          sendPort.send({'type': 'baseUrl', 'baseUrl': baseUrl});
          break;
        }
      } catch (_) {
        continue;
      }
    }

    if (response == null || response.statusCode != 200 || chosenUri == null) {
      throw StateError('Unable to download $relativePath from any server');
    }

    final totalBytes = response.contentLength ?? -1;
    int receivedBytes = 0;
    int lastBytes = 0;
    var lastUpdate = DateTime.now().millisecondsSinceEpoch;

    final sink = tempFile.openWrite();
    await for (final chunk in response.stream) {
      if (cancelSignal.cancelled) {
        await sink.flush();
        await sink.close();
        if (tempFile.existsSync()) {
          await tempFile.delete();
        }
        return;
      }
      sink.add(chunk);
      receivedBytes += chunk.length;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastUpdate >= 150) {
        final bytesDelta = receivedBytes - lastBytes;
        final seconds = (now - lastUpdate) / 1000;
        final speed = seconds > 0 ? bytesDelta / seconds : 0.0;
        lastUpdate = now;
        lastBytes = receivedBytes;

        final progress = totalBytes > 0
            ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
            : 0.0;

        sendPort.send({
          'type': 'progress',
          'path': relativePath,
          'progress': progress,
          'speedBytesPerSec': speed,
          'downloadedBytes': receivedBytes,
          'totalBytes': totalBytes > 0 ? totalBytes : null,
        });
      }
    }

    await sink.flush();
    await sink.close();
    await tempFile.rename(targetPath);

    sendPort.send({
      'type': 'progress',
      'path': relativePath,
      'progress': 1.0,
      'speedBytesPerSec': 0.0,
      'downloadedBytes': receivedBytes,
      'totalBytes': totalBytes > 0 ? totalBytes : null,
    });
  } finally {
    client.close();
  }
}

class _CancelSignal {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}
