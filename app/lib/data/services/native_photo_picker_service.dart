import 'package:flutter/services.dart';
import 'package:dearcocoa/domain/models/native_photo_selection.dart';
import 'package:dearcocoa/domain/models/prepared_photo_attachment.dart';
import 'package:dearcocoa/utils/result.dart';
import 'package:dearcocoa/utils/logger.dart';

class NativePhotoPickerService {
  static const channel = MethodChannel('app.dearcocoa.mobile/photo_picker');

  static Future<Result<List<NativePhotoSelection>>> pick({int maxAssets = 9}) =>
      runResult(() async {
        getLogger('NativePhotoPickerService')
            .fine('Opening system photo picker');
        final rows = await channel
            .invokeListMethod<dynamic>('pickImages', {'maxAssets': maxAssets});
        getLogger('NativePhotoPickerService').fine(
            'System photo picker returned ${(rows ?? []).length} selection(s)');
        return (rows ?? [])
            .map((row) => NativePhotoSelection(
                id: row['id'] as String, assetId: row['assetId'] as String?))
            .toList();
      });

  static Future<Result<Uint8List?>> thumbnail(String id) =>
      runResult(() => channel.invokeMethod<Uint8List>('thumbnail', {'id': id}));

  static Future<Result<PreparedPhotoAttachment>> prepare(String id) =>
      runResult(() async {
        final timer = Stopwatch()..start();
        final row = await channel
            .invokeMapMethod<String, dynamic>('prepareOriginal', {'id': id});
        if (row == null) throw StateError('No photo returned by system picker');
        getLogger('NativePhotoPickerService')
            .fine('System photo prepared in ${timer.elapsedMilliseconds}ms');
        return PreparedPhotoAttachment(
            path: row['path'] as String,
            originalName: row['originalName'] as String);
      });

  static Future<void> release(String id) async {
    await channel.invokeMethod<void>('release', {'id': id});
  }
}
