import 'dart:io';

/// Generates platform runner files without replacing the migrated application.
Future<void> main(List<String> args) async {
  final root = Directory.current;
  if (!File('pubspec.yaml').existsSync())
    throw StateError('Run inside heist_flutter.');
  final staging = await Directory.systemTemp.createTemp(
    'heist_flutter_scaffold_',
  );
  final platforms = args.isEmpty
      ? 'android,ios,web,windows,linux,macos'
      : args.single;
  final result = await Process.run('flutter', [
    '--no-version-check',
    'create',
    '--no-pub',
    '--project-name',
    'heist_flutter',
    '--platforms=$platforms',
    staging.path,
  ], runInShell: Platform.isWindows);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) exit(result.exitCode);
  for (final platform in platforms.split(',').where((p) => p != 'web')) {
    final source = Directory('${staging.path}/$platform');
    final destination = Directory('${root.path}/$platform');
    if (destination.existsSync()) {
      stdout.writeln('Preserving existing $platform runner.');
      continue;
    }
    for (final entity in source.listSync(recursive: true)) {
      final relative = entity.path.substring(source.path.length);
      final target = '${destination.path}$relative';
      if (entity is Directory) Directory(target).createSync(recursive: true);
      if (entity is File) {
        File(target).parent.createSync(recursive: true);
        entity.copySync(target);
      }
    }
  }
  final metadata = File('${staging.path}/.metadata');
  if (metadata.existsSync() && !File('.metadata').existsSync())
    metadata.copySync('${root.path}/.metadata');
  stdout.writeln('Platform runners prepared. Run flutter pub get next.');
  // Keep staging for diagnosis rather than performing recursive deletion.
}
