import 'package:web/web.dart' as web;

/// Read only the planner document, never the old account/credential storage.
/// Leaving the original value untouched permits rollback to the original app.
String? readLegacyDocument() => web.window.localStorage.getItem('heist.v1');
