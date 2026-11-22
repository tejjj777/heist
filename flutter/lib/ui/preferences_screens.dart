part of 'app.dart';

extension _PreferencesScreens on _PlannerShellState {
  List<Widget> settingsPage() {
    return switch (tab) {
      'money' => [
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(tr('Money preferences')),
              Text(
                tr(
                  'Currency changes labels only; existing amounts are not converted.',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(state['currency']),
                initialValue:
                    [
                      'INR',
                      'USD',
                      'EUR',
                      'GBP',
                      'AUD',
                      'CAD',
                    ].contains(state['currency'])
                    ? state['currency']
                    : 'INR',
                decoration: InputDecoration(labelText: tr('Currency')),
                items: [
                  for (final code in ['INR', 'USD', 'EUR', 'GBP', 'AUD', 'CAD'])
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
                onChanged: (v) {
                  if (v != null)
                    act(() => store.mutate((s) => s['currency'] = v));
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payments_outlined),
                title: Text(tr('Income and allowance')),
                trailing: const Icon(Icons.chevron_right),
                onTap: editIncome,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(tr('Bank / UPI balance')),
                trailing: const Icon(Icons.chevron_right),
                onTap: setBank,
              ),
            ],
          ),
        ),
      ],
      'data' => [
        if (widget.sync != null) ...accountPanel(),
        backupPanel(),
        if (widget.sync == null)
          empty(
            tr(
              'Sign-in is needed for cloud sync. Local saving and file backups work offline.',
            ),
          ),
      ],
      'help' => [
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(tr('Getting started')),
              Text(
                tr(
                  'Learn how to plan, scan receipts, save offline and protect your data.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: showTutorial,
                icon: const Icon(Icons.school_outlined),
                label: Text(tr('Replay tutorial')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: working ? null : scanReceipt,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(tr('Scan receipt')),
              ),
            ],
          ),
        ),
        offlineHelpPanel(),
      ],
      _ => [
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(tr('Appearance and privacy')),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Dark mode')),
                value: store.dark,
                onChanged: (v) => act(() => store.setDark(v)),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Hide amounts')),
                subtitle: Text(tr('Hide balances and totals on this device.')),
                value: store.hideAmounts,
                onChanged: (v) =>
                    act(() => store.setPreference('hideAmounts', v)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(store.language),
                initialValue: store.language,
                decoration: InputDecoration(labelText: tr('Language')),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'te', child: Text('తెలుగు')),
                  DropdownMenuItem(value: 'hi', child: Text('हिन्दी')),
                ],
                onChanged: (v) {
                  if (v != null) act(() => store.setPreference('language', v));
                },
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  'Language and privacy preferences are saved offline on this device.',
                ),
              ),
            ],
          ),
        ),
      ],
    };
  }

  Future<void> showTutorial() async {
    if (tutorialScheduled || !mounted) return;
    tutorialScheduled = true;
    var step = 0;
    const steps = [
      (
        'Your money. Your move.',
        'Set your income and opening balance in Budget to see a daily spending limit.',
        Icons.account_balance_wallet_outlined,
      ),
      (
        'Log and scan',
        'Use Log spend for an expense or Scan receipt for camera and gallery OCR. Review the amount before saving.',
        Icons.document_scanner_outlined,
      ),
      (
        'Saved offline first',
        'Your edits are saved to SQLite. Hive keeps preferences and recovery copies. You can keep working without internet.',
        Icons.offline_bolt_outlined,
      ),
      (
        'Sync and backups',
        'Sign in and unlock your vault to sync when internet returns. Export a backup file in Settings → Data. Restoring pauses sync until you review and resume.',
        Icons.cloud_sync_outlined,
      ),
      (
        'Privacy and language',
        'Use the eye button to hide amounts. Choose English, Telugu or Hindi in Settings → Basics. Replay this guide from Help.',
        Icons.visibility_off_outlined,
      ),
    ];
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (c, update) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: Text(tr(steps[step].$1)),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        steps[step].$3,
                        size: 56,
                        color: Theme.of(c).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(tr(steps[step].$2)),
                      const SizedBox(height: 20),
                      LinearProgressIndicator(value: (step + 1) / steps.length),
                      const SizedBox(height: 8),
                      Text('${step + 1} / ${steps.length}'),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await store.setPreference('tutorial.v1', true);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Text(tr('Skip')),
                ),
                if (step > 0)
                  TextButton(
                    onPressed: () => update(() => step--),
                    child: Text(tr('Back')),
                  ),
                FilledButton(
                  onPressed: () async {
                    if (step < steps.length - 1) {
                      update(() => step++);
                      return;
                    }
                    await store.setPreference('tutorial.v1', true);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Text(
                    tr(step == steps.length - 1 ? 'Get started' : 'Next'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      tutorialScheduled = false;
    }
  }

  List<Widget> walletPage() {
    final widgets = wallet();
    final content = switch (tab) {
      'ious' => [split()[1]],
      'subs' => [budget()[4]],
      'transport' => [widgets[5]],
      'income' => [widgets[3], widgets[7]],
      'records' => [widgets[4], widgets[6]],
      _ => widgets.take(3).toList(),
    };
    return [
      box(
        Column(
          children: [
            TextField(
              key: const Key('wallet-search'),
              controller: walletSearchController,
              decoration: InputDecoration(
                labelText: tr('Search wallet'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) =>
                  updateView(() => walletSearch = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final range in [
                  ('all', 'All time'),
                  ('month', 'This month'),
                  ('week', 'Last 7 days'),
                ])
                  ChoiceChip(
                    label: Text(tr(range.$2)),
                    selected: walletRange == range.$1,
                    onSelected: (_) => updateView(() => walletRange = range.$1),
                  ),
              ],
            ),
            if (tab == 'cash')
              Wrap(
                spacing: 8,
                children: [
                  for (final direction in [
                    ('all', 'All entries'),
                    ('in', 'Cash in'),
                    ('out', 'Cash out'),
                  ])
                    ChoiceChip(
                      label: Text(tr(direction.$2)),
                      selected: walletDirection == direction.$1,
                      onSelected: (_) =>
                          updateView(() => walletDirection = direction.$1),
                    ),
                ],
              ),
            if (walletSearch.isNotEmpty ||
                walletRange != 'all' ||
                walletDirection != 'all')
              TextButton(
                onPressed: () => updateView(() {
                  walletSearch = '';
                  walletSearchController.clear();
                  walletRange = 'all';
                  walletDirection = 'all';
                }),
                child: Text(tr('Clear filters')),
              ),
          ],
        ),
      ),
      ...content,
    ];
  }

  bool walletMatches(String path, Json row) {
    if (walletSearch.isNotEmpty &&
        !row.values
            .whereType<String>()
            .join(' ')
            .toLowerCase()
            .contains(walletSearch))
      return false;
    if (path == 'wallet.cash' &&
        walletDirection != 'all' &&
        row['type'] != walletDirection)
      return false;
    if (walletRange == 'all') return true;
    final date = DateTime.tryParse(
      (row['date'] ?? row['since'] ?? row['due'] ?? '${row['month']}-01')
          .toString(),
    );
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = walletRange == 'month'
        ? DateTime(now.year, now.month)
        : today.subtract(const Duration(days: 6));
    return !date.isBefore(start) &&
        date.isBefore(today.add(const Duration(days: 1)));
  }
}
