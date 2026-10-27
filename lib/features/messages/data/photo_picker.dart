import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// A photo the person chose, already in memory.
class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

/// Choosing a photo, behind an interface.
///
/// `image_picker` is a platform channel and `flutter test` has none, so every
/// test of the message screen would otherwise be at the mercy of a plugin
/// that cannot answer. The same reason `AppLauncher` and `DeviceStatusReader`
/// are interfaces.
abstract interface class PhotoPicker {
  /// Null when they backed out, which is not a failure and must not be drawn
  /// as one.
  Future<PickedPhoto?> pick();
}

class ImagePickerPhotoPicker implements PhotoPicker {
  const ImagePickerPhotoPicker();

  @override
  Future<PickedPhoto?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Phone cameras produce 12MP files and the bucket stops at 8MB. This
      // is also kindness on a parent's data plan: nobody is reading a family
      // snapshot at full sensor resolution on a 6-inch screen.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null) return null;
    return PickedPhoto(
      bytes: await file.readAsBytes(),
      // `pickImage` re-encodes to JPEG once maxWidth/imageQuality are set,
      // whatever the original was. Reading the extension back would be
      // guessing at what the plugin already decided.
      contentType: 'image/jpeg',
    );
  }
}

/// What the tests and the review screenshots use.
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker({this.photo});

  /// A picker the person backed out of.
  FakePhotoPicker.cancelled() : photo = null;

  final PickedPhoto? photo;
  int calls = 0;

  @override
  Future<PickedPhoto?> pick() async {
    calls++;
    return photo;
  }
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => const ImagePickerPhotoPicker(),
);
