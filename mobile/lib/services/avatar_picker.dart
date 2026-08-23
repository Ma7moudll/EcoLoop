import 'package:image_picker/image_picker.dart';

/// Picks a photo from the device gallery for the profile avatar.
/// Returns the copied file path, or null when the user cancels.
Future<String?> pickImageFromGallery() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 768,
    maxHeight: 768,
    imageQuality: 85,
  );
  return picked?.path;
}
