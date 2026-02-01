import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'viewmodels/main_view_model.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final MainViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = MainViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('FLUX2 Text-to-Image')),
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _viewModel,
            builder: (context, _) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(
                      label: 'Prompt',
                      controller: _viewModel.promptController,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'Width',
                            controller: _viewModel.widthController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            label: 'Height',
                            controller: _viewModel.heightController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            label: 'Steps',
                            controller: _viewModel.stepsController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            label: 'Seed',
                            controller: _viewModel.seedController,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildModelPathSection(context),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Use mmap'),
                      value: _viewModel.useMmap,
                      onChanged: (value) {
                        _viewModel.useMmap = value;
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Release text encoder after run'),
                      value: _viewModel.releaseTextEncoder,
                      onChanged: (value) {
                        _viewModel.releaseTextEncoder = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    if (!_viewModel.areModelFilesAvailable) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _viewModel.isDownloading
                                  ? null
                                  : _viewModel.downloadModel,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                _viewModel.isDownloading
                                    ? 'Downloading...'
                                    : 'Download Model',
                              ),
                            ),
                          ),
                          if (_viewModel.isDownloading) ...[
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _viewModel.cancelDownload,
                              icon: const Icon(Icons.close),
                              label: const Text('Cancel'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_viewModel.downloadItems.isNotEmpty) ...[
                        Text(
                          'Model files',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildDownloadList(_viewModel.downloadItems),
                      ],
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _viewModel.isGenerating
                              ? null
                              : _viewModel.generateImage,
                          child: Text(
                            _viewModel.isGenerating
                                ? 'Generating...'
                                : 'Generate Image',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      _viewModel.statusMessage,
                      style: TextStyle(
                        color: _viewModel.statusMessage.startsWith('Error')
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                    if (_viewModel.lastImagePath != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_viewModel.lastImagePath!),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Text(
                            'Failed to load image: $error',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildModelPathSection(BuildContext context) {
    final modelDir = _viewModel.modelDirPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Model directory',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  modelDir.isEmpty ? 'Not set' : modelDir,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 12,
                    color: modelDir.isEmpty ? Colors.grey : Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Copy path',
              icon: const Icon(Icons.copy),
              onPressed: modelDir.isEmpty
                  ? null
                  : () => _copyToClipboard(context, modelDir),
            ),
          ],
        ),
        if (modelDir.isEmpty) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: _viewModel.ensureModelDir,
            child: const Text('Set default path'),
          ),
        ],
      ],
    );
  }

  Future<void> _copyToClipboard(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Model path copied')));
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond == 0) return '';

    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else if (bytesPerSecond < 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
    }
  }

  Widget _buildDownloadList(List<DownloadItem> items) {
    return Column(children: items.map(_buildDownloadItem).toList());
  }

  Widget _buildDownloadItem(DownloadItem item) {
    final isDownloading = item.state == DownloadItemState.downloading;
    final isCompleted = item.state == DownloadItemState.completed;
    final isFailed = item.state == DownloadItemState.failed;

    final progressValue = isCompleted
        ? 1.0
        : (isDownloading ? item.progress : 0.0);
    final percent = (progressValue * 100).clamp(0, 100).toStringAsFixed(0);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isCompleted) {
      statusColor = Colors.green;
      statusLabel = 'Completed';
      statusIcon = Icons.check_circle;
    } else if (isDownloading) {
      statusColor = Colors.blue;
      statusLabel = 'Downloading';
      statusIcon = Icons.downloading;
    } else if (isFailed) {
      statusColor = Colors.red;
      statusLabel = 'Failed';
      statusIcon = Icons.error;
    } else {
      statusColor = Colors.grey;
      statusLabel = 'Pending';
      statusIcon = Icons.schedule;
    }

    final speedLabel = isDownloading ? _formatSpeed(item.speedBytesPerSec) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.fileName,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progressValue,
            backgroundColor: Colors.grey[200],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                statusLabel,
                style: TextStyle(fontSize: 11, color: statusColor),
              ),
              if (speedLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  speedLabel,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
