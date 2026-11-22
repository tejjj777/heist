import 'package:web/web.dart' as web;

Uri? takeIncomingAuthLink() {
  final uri = Uri.base;
  final fields = Uri.splitQueryString(uri.fragment);
  if (!fields.containsKey('access_token') && !fields.containsKey('error'))
    return null;
  web.window.history.replaceState(
    null,
    '',
    '${web.window.location.pathname}#/dashboard/overview',
  );
  return uri;
}
