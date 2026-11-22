part of 'app.dart';

extension AccountTools on _PlannerShellState {
  Future<void> rotateVaultKeys() async {
    final sync = widget.sync!;
    final form = await editRecord(context, 'Change vault protection', const [
      Field('current', 'Current passphrase or recovery key', obscure: true),
      Field(
        'method',
        'Current key type',
        choices: {'pass': 'Passphrase', 'recovery': 'Recovery key'},
      ),
      Field('next', 'New passphrase (at least 8 characters)', obscure: true),
      Field('repeat', 'Repeat new passphrase', obscure: true),
    ]);
    if (form == null) return;
    if (form['next'] != form['repeat'] || (form['next'] as String).length < 8) {
      message('Use matching passphrases of at least 8 characters.');
      return;
    }
    await act(() async {
      final wasPaused = await store.synchronizationPaused();
      await store.pauseSynchronization(true);
      String? recovery;
      try {
        if (sync.busy)
          throw const FormatException(
            'Wait for synchronization to finish, then try again.',
          );
        final row = await sync.backend.vault();
        if (row == null)
          throw const FormatException('No account vault was found.');
        if (number(row['version']).toInt() != await store.remoteVersion()) {
          throw const FormatException(
            'Synchronize and resolve any conflict before changing vault protection.',
          );
        }
        final key = form['method'] == 'recovery'
            ? await sync.crypto.openRecovery(row, form['current'])
            : await sync.crypto.openPass(row, form['current']);
        if (key != sync.backend.dataKey)
          throw const FormatException(
            'The unlocked vault key does not match this device.',
          );
        // Rewrap the existing data key. The encrypted account document is unchanged.
        final wrapped = await sync.crypto.rewrap(key, form['next']);
        final version = number(row['version']).toInt();
        final updated = rows(
          await sync.backend.request(
            '/rest/v1/vaults?user_id=eq.${sync.backend.uid}&version=eq.$version',
            method: 'PATCH',
            prefer: 'return=representation',
            body: {
              ...wrapped.fields,
              'version': version + 1,
              'device': 'Flutter',
            },
          ),
        );
        if (updated.isEmpty)
          throw const FormatException(
            'The account changed elsewhere. No keys were replaced; synchronize and try again.',
          );
        await store.acknowledge(sync.backend.uid!, 0, version + 1);
        recovery = wrapped.recovery;
      } finally {
        await store.pauseSynchronization(wasPaused);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('Save the new recovery key'),
          content: SelectableText(
            'The old passphrase and recovery key no longer unlock this vault.\n\n$recovery',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('I saved the key'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> deleteCloudAccount() async {
    final value = await editRecord(context, 'Delete cloud account', const [
      Field('confirm', 'Type DELETE to permanently delete the cloud account'),
    ]);
    if (value?['confirm'] != 'DELETE' || !mounted) return;
    if (!await confirm(
      context,
      'Permanently delete cloud account?',
      'This deletes the remote vault and account. Export your backup first. This device’s planner remains available.',
    ))
      return;
    await act(() async {
      await store.pauseSynchronization(true);
      await widget.sync!.backend.request(
        '/rest/v1/rpc/delete_my_account',
        method: 'POST',
        body: {},
      );
      await widget.sync!.backend.signOut();
      await store.unbindAccount();
      message('Cloud account deleted. Local data has been retained.');
    });
  }
}
