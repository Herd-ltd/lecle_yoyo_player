import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileUtils {
  static void cacheFileToLocalStorage(
    String videoUrl, {
    Map<String, String>? headers,
    String? fileExtension,
    void Function(File? file)? onSaveCompleted,
    void Function(dynamic err)? onSaveFailed,
  }) {
    final http.Client client = http.Client();
    client.get(Uri.parse(videoUrl), headers: headers).then((response) {
      if (response.statusCode != 200) return;
      final fileName = _getFileNameFromUrl(videoUrl);
      _writeFile(
        response: response,
        fileExtension: fileExtension,
        onSaveCompleted: onSaveCompleted,
        onSaveFailed: onSaveFailed,
        fileName: fileName,
      );
    }).catchError((dynamic err) {
      onSaveFailed?.call(err);
    });
  }

  static Future<void> _writeFile({
    required http.Response response,
    String? fileExtension,
    void Function(File file)? onSaveCompleted,
    void Function(dynamic err)? onSaveFailed,
    String? fileName,
  }) async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    if (dir != null) {
      final File file = File(
        '${dir.path}/${(fileName != null && fileName.isNotEmpty) ? fileName : DateTime.now().millisecondsSinceEpoch}.${fileExtension ?? 'm3u8'}',
      );
      await file
          .writeAsBytes(response.bodyBytes)
          .then((f) => onSaveCompleted?.call(f))
          .catchError((dynamic err) => onSaveFailed?.call(err));
    }
  }

  static String _getFileNameFromUrl(String? videoUrl) {
    if (videoUrl != null) {
      return p.basenameWithoutExtension(videoUrl);
    }

    return '';
  }

  static Future<File?> cacheFileUsingWriteAsString({
    required String contents,
    required String quality,
    required String videoUrl,
  }) async {
    final name = _getFileNameFromUrl(videoUrl);

    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    final File file = File(
      '${directory?.path ?? ''}/yoyo_${name.isNotEmpty ? '${name}_' : name}$quality.m3u8',
    );
    try {
      return await file.writeAsString(contents);
    } on Exception {
      return null;
    }
  }

  static Future<File?> readFileFromPath({
    required String videoUrl,
    required String quality,
  }) async {
    final name = _getFileNameFromUrl(videoUrl);

    Directory? directory;

    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    final File file = File(
      '${directory?.path ?? ''}/yoyo_${name.isNotEmpty ? '${name}_' : name}$quality.m3u8',
    );

    final exists = file.existsSync();
    if (exists) return file;
    return null;
  }
}
