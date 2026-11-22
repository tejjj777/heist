import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<String> recognizeReceipt(XFile file) async {
  if (!Platform.isAndroid && !Platform.isIOS)
    throw UnsupportedError('Use the web or mobile app for receipt OCR.');
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    return (await recognizer.processImage(
      InputImage.fromFilePath(file.path),
    )).text;
  } finally {
    await recognizer.close();
  }
}
