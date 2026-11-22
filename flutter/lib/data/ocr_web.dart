import 'dart:convert';
import 'dart:js_interop';
import 'package:file_selector/file_selector.dart';

@JS('heistRecognize')
external JSPromise<JSString> _recognize(JSString data);
Future<String> recognizeReceipt(XFile file) async {
  final bytes = await file.readAsBytes();
  if (bytes.length > 20 * 1024 * 1024)
    throw const FormatException('Image exceeds 20 MB.');
  return (await _recognize(
    'data:${file.mimeType ?? 'image/png'};base64,${base64Encode(bytes)}'.toJS,
  ).toDart).toDart;
}
