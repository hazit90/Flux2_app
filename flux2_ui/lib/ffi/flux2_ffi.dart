import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

final class Flux2Params extends ffi.Struct {
  @ffi.Int32()
  external int width;

  @ffi.Int32()
  external int height;

  @ffi.Int32()
  external int numSteps;

  @ffi.Int64()
  external int seed;

  @ffi.Int32()
  external int useMmap;

  @ffi.Int32()
  external int releaseTextEncoder;
}

class Flux2ParamsData {
  const Flux2ParamsData({
    this.width = 256,
    this.height = 256,
    this.numSteps = 4,
    this.seed = -1,
    this.useMmap = 1,
    this.releaseTextEncoder = 1,
  });

  final int width;
  final int height;
  final int numSteps;
  final int seed;
  final int useMmap;
  final int releaseTextEncoder;
}

typedef _Flux2LoadModelNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<Utf8> modelDir,
      ffi.Pointer<Flux2Params> params,
    );
typedef _Flux2LoadModelDart =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<Utf8> modelDir,
      ffi.Pointer<Flux2Params> params,
    );

typedef _Flux2FreeModelNative = ffi.Void Function(ffi.Pointer<ffi.Void> ctx);
typedef _Flux2FreeModelDart = void Function(ffi.Pointer<ffi.Void> ctx);

typedef _Flux2LastErrorNative = ffi.Pointer<Utf8> Function();
typedef _Flux2LastErrorDart = ffi.Pointer<Utf8> Function();

typedef _Flux2GenerateToFileNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> ctx,
      ffi.Pointer<Utf8> prompt,
      ffi.Pointer<Utf8> outputPath,
      ffi.Pointer<Flux2Params> params,
    );
typedef _Flux2GenerateToFileDart =
    int Function(
      ffi.Pointer<ffi.Void> ctx,
      ffi.Pointer<Utf8> prompt,
      ffi.Pointer<Utf8> outputPath,
      ffi.Pointer<Flux2Params> params,
    );

typedef _Flux2GenerateToFileWithModelNative =
    ffi.Int32 Function(
      ffi.Pointer<Utf8> modelDir,
      ffi.Pointer<Utf8> prompt,
      ffi.Pointer<Utf8> outputPath,
      ffi.Pointer<Flux2Params> params,
    );
typedef _Flux2GenerateToFileWithModelDart =
    int Function(
      ffi.Pointer<Utf8> modelDir,
      ffi.Pointer<Utf8> prompt,
      ffi.Pointer<Utf8> outputPath,
      ffi.Pointer<Flux2Params> params,
    );

class Flux2Bindings {
  Flux2Bindings({ffi.DynamicLibrary? library})
    : _lib = library ?? _openDynamicLibrary();

  final ffi.DynamicLibrary _lib;

  late final _Flux2LoadModelDart _loadModel = _lib
      .lookupFunction<_Flux2LoadModelNative, _Flux2LoadModelDart>(
        'flux2_load_model',
      );

  late final _Flux2FreeModelDart _freeModel = _lib
      .lookupFunction<_Flux2FreeModelNative, _Flux2FreeModelDart>(
        'flux2_free_model',
      );

  late final _Flux2LastErrorDart _lastError = _lib
      .lookupFunction<_Flux2LastErrorNative, _Flux2LastErrorDart>(
        'flux2_last_error',
      );

  late final _Flux2GenerateToFileDart _generateToFile = _lib
      .lookupFunction<_Flux2GenerateToFileNative, _Flux2GenerateToFileDart>(
        'flux2_generate_to_file',
      );

  late final _Flux2GenerateToFileWithModelDart _generateToFileWithModel = _lib
      .lookupFunction<
        _Flux2GenerateToFileWithModelNative,
        _Flux2GenerateToFileWithModelDart
      >('flux2_generate_to_file_with_model');

  ffi.Pointer<ffi.Void> loadModel(String modelDir, Flux2ParamsData params) {
    final modelDirPtr = modelDir.toNativeUtf8();
    final paramsPtr = calloc<Flux2Params>();
    paramsPtr.ref
      ..width = params.width
      ..height = params.height
      ..numSteps = params.numSteps
      ..seed = params.seed
      ..useMmap = params.useMmap
      ..releaseTextEncoder = params.releaseTextEncoder;

    final ctx = _loadModel(modelDirPtr, paramsPtr);
    calloc.free(modelDirPtr);
    calloc.free(paramsPtr);
    return ctx;
  }

  void freeModel(ffi.Pointer<ffi.Void> ctx) {
    _freeModel(ctx);
  }

  String lastError() {
    final ptr = _lastError();
    if (ptr == ffi.nullptr) {
      return 'Unknown error';
    }
    return ptr.toDartString();
  }

  int generateToFile({
    required ffi.Pointer<ffi.Void> ctx,
    required String prompt,
    required String outputPath,
    Flux2ParamsData? params,
  }) {
    final promptPtr = prompt.toNativeUtf8();
    final outputPtr = outputPath.toNativeUtf8();
    final paramsPtr = params != null ? calloc<Flux2Params>() : ffi.nullptr;
    if (params != null) {
      paramsPtr.ref
        ..width = params.width
        ..height = params.height
        ..numSteps = params.numSteps
        ..seed = params.seed
        ..useMmap = params.useMmap
        ..releaseTextEncoder = params.releaseTextEncoder;
    }

    final result = _generateToFile(ctx, promptPtr, outputPtr, paramsPtr);
    calloc.free(promptPtr);
    calloc.free(outputPtr);
    if (params != null) {
      calloc.free(paramsPtr);
    }
    return result;
  }

  int generateToFileWithModel({
    required String modelDir,
    required String prompt,
    required String outputPath,
    Flux2ParamsData? params,
  }) {
    final modelPtr = modelDir.toNativeUtf8();
    final promptPtr = prompt.toNativeUtf8();
    final outputPtr = outputPath.toNativeUtf8();
    final paramsPtr = params != null ? calloc<Flux2Params>() : ffi.nullptr;
    if (params != null) {
      paramsPtr.ref
        ..width = params.width
        ..height = params.height
        ..numSteps = params.numSteps
        ..seed = params.seed
        ..useMmap = params.useMmap
        ..releaseTextEncoder = params.releaseTextEncoder;
    }

    final result = _generateToFileWithModel(
      modelPtr,
      promptPtr,
      outputPtr,
      paramsPtr,
    );
    calloc.free(modelPtr);
    calloc.free(promptPtr);
    calloc.free(outputPtr);
    if (params != null) {
      calloc.free(paramsPtr);
    }
    return result;
  }

  static ffi.DynamicLibrary _openDynamicLibrary() {
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isMacOS) {
      final exePath = File(Platform.resolvedExecutable).parent.path;
      final bundleLib = '$exePath/libflux2_wrapper.dylib';
      if (File(bundleLib).existsSync()) {
        return ffi.DynamicLibrary.open(bundleLib);
      }
      return ffi.DynamicLibrary.open('libflux2_wrapper.dylib');
    }
    if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libflux2_wrapper.so');
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('flux2_wrapper.dll');
    }
    throw UnsupportedError('Unsupported platform');
  }
}
