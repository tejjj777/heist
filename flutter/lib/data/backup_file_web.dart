import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<bool> saveBackupFile(String name, String text) async {
  final blob = web.Blob(
    [utf8.encode(text).toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(link);
  link.click();
  link.remove();
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
  return true;
}
