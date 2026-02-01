import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ffi/flux2_ffi.dart';
import '../services/download_manager.dart';

class MainViewModel extends ChangeNotifier {
  MainViewModel() {
    unawaited(_initDefaultModelDir());
  }

  final modelDirController = TextEditingController();
  final promptController = TextEditingController(
    text: 'A fluffy orange cat sitting on a windowsill',
  );
  final widthController = TextEditingController(text: '256');
  final heightController = TextEditingController(text: '256');
  final stepsController = TextEditingController(text: '4');
  final seedController = TextEditingController(text: '-1');

  bool _useMmap = true;
  bool _releaseTextEncoder = true;
  bool _isGenerating = false;
  bool _isDownloading = false;
  String _statusMessage = '';
  String? _lastImagePath;
  List<DownloadItem> _downloadItems = [];
  StreamSubscription<Map<String, dynamic>>? _downloadSubscription;

  final Flux2Bindings _bindings = Flux2Bindings();
  final DownloadManager _downloadManager = DownloadManager();

  bool get useMmap => _useMmap;
  bool get releaseTextEncoder => _releaseTextEncoder;
  bool get isGenerating => _isGenerating;
  bool get isDownloading => _isDownloading;
  String get statusMessage => _statusMessage;
  String? get lastImagePath => _lastImagePath;
  List<DownloadItem> get downloadItems => _downloadItems;
  bool get areModelFilesAvailable => _checkModelFilesAvailable();
  String get modelDirPath => modelDirController.text.trim();
  bool get hasPendingDownloads =>
      _downloadItems.any((item) => item.state != DownloadItemState.completed);

  set useMmap(bool value) {
    if (_useMmap == value) return;
    _useMmap = value;
    notifyListeners();
  }

  set releaseTextEncoder(bool value) {
    if (_releaseTextEncoder == value) return;
    _releaseTextEncoder = value;
    notifyListeners();
  }

  Future<void> generateImage() async {
    if (_isGenerating) return;

    _isGenerating = true;
    _statusMessage = 'Generating...';
    notifyListeners();

    try {
      final modelDir = (await _resolveModelDir()).trim();
      if (modelDir.isEmpty) {
        _lastImagePath = null;
        _statusMessage = 'Model directory is not set';
        return;
      }

      final modelDirEntity = Directory(modelDir);
      if (!modelDirEntity.existsSync()) {
        _lastImagePath = null;
        _statusMessage = 'Model directory not found: $modelDir';
        return;
      }

      if (!_checkModelFilesAvailable(modelDir)) {
        _lastImagePath = null;
        _statusMessage = 'Model files are missing in: $modelDir';
        _refreshDownloadList(modelDir);
        return;
      }

      final params = _buildParams();
      final outputPath = _buildOutputPath();
      final result = _bindings.generateToFileWithModel(
        modelDir: modelDir,
        prompt: promptController.text.trim(),
        outputPath: outputPath,
        params: params,
      );

      if (result == 0) {
        _lastImagePath = outputPath;
        _statusMessage = 'Done';
      } else {
        _lastImagePath = null;
        _statusMessage = 'Error ($result): ${_bindings.lastError()}';
      }
    } catch (error) {
      _lastImagePath = null;
      _statusMessage = 'Error: $error';
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> downloadModel() async {
    if (_isDownloading) return;

    final modelDir = await _resolveModelDir();
    _refreshDownloadList(modelDir);
    if (_checkModelFilesAvailable(modelDir)) {
      _statusMessage = 'Model files already downloaded';
      notifyListeners();
      return;
    }

    _isDownloading = true;
    _statusMessage = 'Downloading model...';
    notifyListeners();

    await _downloadSubscription?.cancel();
    _downloadSubscription = _downloadManager.events.listen(
      _handleDownloadEvent,
    );

    try {
      await _downloadManager.downloadFiles(
        modelDir: modelDir,
        requiredFiles: DownloadManager.requiredFiles,
      );
      _statusMessage = 'Model ready';
    } catch (error) {
      _statusMessage = 'Download error: $error';
    } finally {
      _isDownloading = false;
      await _downloadSubscription?.cancel();
      _downloadSubscription = null;
      _refreshDownloadList(modelDir);
      notifyListeners();
    }
  }

  void cancelDownload() {
    if (!_isDownloading) return;
    _downloadManager.cancel();
    _statusMessage = 'Download cancelled';
    _isDownloading = false;
    _refreshDownloadList();
    notifyListeners();
  }

  @override
  void dispose() {
    _downloadManager.dispose();
    _downloadSubscription?.cancel();
    modelDirController.dispose();
    promptController.dispose();
    widthController.dispose();
    heightController.dispose();
    stepsController.dispose();
    seedController.dispose();
    super.dispose();
  }

  Future<void> _initDefaultModelDir() async {
    if (modelDirController.text.trim().isNotEmpty) return;

    if (Platform.isIOS) {
      final bundleDir = Directory(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$bundleDir/assets/flux-klein-model',
        '$bundleDir/flux-klein-model',
      ];

      for (final path in candidates) {
        if (Directory(path).existsSync()) {
          modelDirController.text = path;
          _refreshDownloadList(path);
          notifyListeners();
          return;
        }
      }
    }

    await _resolveModelDir();
    _refreshDownloadList();
  }

  Future<void> ensureModelDir() async {
    await _resolveModelDir();
    _refreshDownloadList();
  }

  bool _checkModelFilesAvailable([String? modelDirPath]) {
    final modelDir = (modelDirPath ?? modelDirController.text).trim();
    if (modelDir.isEmpty) return false;

    for (final relativePath in DownloadManager.requiredFiles) {
      final filePath = p.join(modelDir, relativePath);
      if (!File(filePath).existsSync()) {
        return false;
      }
    }
    return true;
  }

  Future<String> _resolveModelDir() async {
    final current = modelDirController.text.trim();
    if (current.isNotEmpty) {
      return current;
    }

    final baseDir = await getApplicationSupportDirectory();
    final modelDir = p.join(baseDir.path, 'flux-klein-model');
    modelDirController.text = modelDir;
    notifyListeners();
    return modelDir;
  }

  void _refreshDownloadList([String? modelDirPath]) {
    final modelDir = (modelDirPath ?? modelDirController.text).trim();
    if (modelDir.isEmpty) {
      _downloadItems = DownloadManager.requiredFiles
          .map(
            (path) => DownloadItem(
              relativePath: path,
              state: DownloadItemState.pending,
              progress: 0.0,
              speedBytesPerSec: 0.0,
            ),
          )
          .toList();
      return;
    }

    _downloadItems = DownloadManager.requiredFiles.map((path) {
      final filePath = p.join(modelDir, path);
      final exists = File(filePath).existsSync();
      return DownloadItem(
        relativePath: path,
        state: exists ? DownloadItemState.completed : DownloadItemState.pending,
        progress: exists ? 1.0 : 0.0,
        speedBytesPerSec: 0.0,
      );
    }).toList();
  }

  void _handleDownloadEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'queue') {
      final items = (event['items'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(DownloadItem.fromMap)
          .toList();
      _downloadItems = items;
      notifyListeners();
      return;
    }

    if (type == 'status') {
      final path = event['path'] as String?;
      final status = event['status'] as String?;
      if (path != null && status != null) {
        _updateItemState(path, status);
        notifyListeners();
      }
      return;
    }

    if (type == 'progress') {
      final path = event['path'] as String?;
      if (path == null) return;
      final progress = (event['progress'] as num?)?.toDouble() ?? 0.0;
      final speed = (event['speedBytesPerSec'] as num?)?.toDouble() ?? 0.0;
      _updateItemProgress(path, progress, speed);
      notifyListeners();
      return;
    }

    if (type == 'error') {
      final message = event['message'] ?? 'Download failed';
      _statusMessage = 'Download error: $message';
      notifyListeners();
    }
  }

  void _updateItemState(String path, String status) {
    final state = DownloadItemState.fromString(status);
    final index = _downloadItems.indexWhere(
      (item) => item.relativePath == path,
    );
    if (index == -1) return;
    final item = _downloadItems[index];
    _downloadItems[index] = item.copyWith(
      state: state,
      progress: state == DownloadItemState.completed ? 1.0 : item.progress,
      speedBytesPerSec: state == DownloadItemState.downloading
          ? item.speedBytesPerSec
          : 0.0,
    );
  }

  void _updateItemProgress(
    String path,
    double progress,
    double speedBytesPerSec,
  ) {
    for (var i = 0; i < _downloadItems.length; i++) {
      final item = _downloadItems[i];
      if (item.relativePath == path) {
        _downloadItems[i] = item.copyWith(
          state: DownloadItemState.downloading,
          progress: progress,
          speedBytesPerSec: speedBytesPerSec,
        );
      } else if (item.state == DownloadItemState.downloading) {
        _downloadItems[i] = item.copyWith(
          state: DownloadItemState.pending,
          speedBytesPerSec: 0.0,
        );
      }
    }
  }

  Flux2ParamsData _buildParams() {
    return Flux2ParamsData(
      width: int.tryParse(widthController.text.trim()) ?? 256,
      height: int.tryParse(heightController.text.trim()) ?? 256,
      numSteps: int.tryParse(stepsController.text.trim()) ?? 4,
      seed: int.tryParse(seedController.text.trim()) ?? -1,
      useMmap: _useMmap ? 1 : 0,
      releaseTextEncoder: _releaseTextEncoder ? 1 : 0,
    );
  }

  String _buildOutputPath() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${Directory.systemTemp.path}/flux_output_$timestamp.png';
  }
}

enum DownloadItemState {
  pending,
  downloading,
  completed,
  failed,
  cancelled;

  static DownloadItemState fromString(String value) {
    switch (value) {
      case 'downloading':
        return DownloadItemState.downloading;
      case 'completed':
        return DownloadItemState.completed;
      case 'failed':
        return DownloadItemState.failed;
      case 'cancelled':
        return DownloadItemState.cancelled;
      default:
        return DownloadItemState.pending;
    }
  }
}

class DownloadItem {
  DownloadItem({
    required this.relativePath,
    required this.state,
    required this.progress,
    required this.speedBytesPerSec,
  });

  final String relativePath;
  final DownloadItemState state;
  final double progress;
  final double speedBytesPerSec;

  String get fileName => p.basename(relativePath);

  DownloadItem copyWith({
    DownloadItemState? state,
    double? progress,
    double? speedBytesPerSec,
  }) {
    return DownloadItem(
      relativePath: relativePath,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
    );
  }

  static DownloadItem fromMap(Map<String, dynamic> map) {
    final path = map['path'] as String? ?? '';
    final status = map['status'] as String? ?? 'pending';
    final progress = (map['progress'] as num?)?.toDouble() ?? 0.0;
    return DownloadItem(
      relativePath: path,
      state: DownloadItemState.fromString(status),
      progress: progress,
      speedBytesPerSec: 0.0,
    );
  }
}
