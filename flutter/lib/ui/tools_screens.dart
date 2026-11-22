part of 'app.dart';

extension _MoneyTools on _PlannerShellState {
  List<Widget> payoffPlannerView() {
    final settings = state['debtSettings'] as Map;
    final debts = rows(
      state['debts'],
    ).where((d) => number(d['balance']) > 0).toList();
    final result = simulatePayoff(
      debts,
      number(settings['extra']),
      settings['strategy']?.toString() ?? 'avalanche',
    );
    return [
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('Your payoff strategy'),
            Wrap(
              spacing: 12,
              children: [
                for (final option in ['avalanche', 'snowball'])
                  ChoiceChip(
                    label: Text(
                      option == 'avalanche'
                          ? 'Highest interest first'
                          : 'Smallest debt first',
                    ),
                    selected: settings['strategy'] == option,
                    onSelected: (_) => act(
                      () => store.mutate(
                        (s) => s['debtSettings']['strategy'] = option,
                      ),
                    ),
                  ),
              ],
            ),
            TextButton(
              onPressed: () async {
                final value = await editRecord(
                  context,
                  'Extra monthly payment',
                  const [Field('extra', 'Extra per month', numeric: true)],
                  record: {'extra': settings['extra'] ?? 0},
                );
                if (value != null)
                  await act(
                    () => store.mutate(
                      (s) => s['debtSettings']['extra'] = value['extra'],
                    ),
                  );
              },
              child: Text('Extra: ${money(settings['extra'])} per month'),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 16,
        children: [
          stat(
            'Payoff',
            result.paidOff
                ? '${result.months.length} months'
                : 'Increase your payment',
            subtitle: 'Estimate with fixed rates and no new borrowing',
          ),
          stat('Estimated interest', money(result.interestMinor / 100)),
        ],
      ),
      for (final row in result.months)
        box(
          Row(
            children: [
              Expanded(
                child: Text(
                  'Month ${row['month']}\nInterest ${money(row['interest'])}',
                ),
              ),
              Flexible(
                child: Text(
                  'Pay ${money(row['payment'])}\nLeft ${money(row['balance'])}',
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> loanCalculatorView() {
    final loan =
        (state['emi'] as Map?) ?? {'principal': 0, 'rate': 0, 'months': 12};
    final schedule = amortization(
      number(loan['principal']),
      number(loan['rate']),
      number(loan['months']).toInt().clamp(1, 600),
    );
    return [
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('Loan calculator'),
            Text(
              '${money(loan['principal'])} · ${loan['rate']}% APR · ${loan['months']} months',
            ),
            TextButton(
              onPressed: () async {
                final value = await editRecord(context, 'Loan details', const [
                  Field('principal', 'Principal', numeric: true),
                  Field('rate', 'Annual interest %', numeric: true, max: 100),
                  Field('months', 'Months', numeric: true, max: 600),
                ], record: Map<String, dynamic>.from(loan));
                if (value == null) return;
                if (number(value['months']) < 1) {
                  message('Enter at least one month.');
                  return;
                }
                await act(() => store.mutate((s) => s['emi'] = value));
              },
              child: const Text('Edit loan'),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 16,
        children: [
          stat('Monthly payment', money(schedule.first['payment'])),
          stat(
            'Total interest',
            money(
              schedule.fold<double>(0, (s, r) => s + number(r['interest'])),
            ),
          ),
        ],
      ),
      for (final row in schedule)
        box(
          Row(
            children: [
              Expanded(
                child: Text(
                  'Month ${row['month']}\nPrincipal ${money(row['principal'])} · Interest ${money(row['interest'])}',
                ),
              ),
              Flexible(child: Text('Balance ${money(row['balance'])}')),
            ],
          ),
        ),
    ];
  }

  Future<void> transactionImport({String? recognizedText}) async {
    try {
      String? text = recognizedText;
      if (text == null) {
        final mode = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Import transactions'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'paste'),
                child: const Text('Paste bank SMS or CSV'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'file'),
                child: const Text('Choose CSV / text file'),
              ),
            ],
          ),
        );
        if (mode == null) return;
        if (mode == 'file') {
          final file = await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: 'Bank statement',
                extensions: ['csv', 'txt'],
                mimeTypes: ['text/csv', 'text/plain'],
              ),
            ],
          );
          if (file == null) return;
          if (await file.length() > 10 * 1024 * 1024)
            throw const FormatException('Statement exceeds 10 MB.');
          text = await file.readAsString();
        } else {
          if (!mounted) return;
          final value = await editRecord(
            context,
            'Paste statement or bank messages',
            const [Field('text', 'Statement / messages', lines: 8)],
          );
          if (value == null) return;
          text = value['text'];
        }
      }
      final candidates = parseTransactions(
        text!,
        today: planner.today,
        monthFirst: state['settings']['country'] == 'US',
      );
      final existing = {
        ...planner.expenses.map(transactionFingerprint),
        ...rows(state['incomeLog']).map(transactionFingerprint),
      };
      final unique = <Json>[];
      for (final row in candidates) {
        if (existing.add(transactionFingerprint(row))) unique.add(row);
      }
      if (unique.isEmpty) {
        message(
          candidates.isEmpty
              ? 'No supported transactions found. Review the source and use Log spend.'
              : 'All recognized transactions are already recorded.',
        );
        return;
      }
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Review ${unique.length} transactions'),
          content: SizedBox(
            width: 520,
            height: 360,
            child: ListView(
              children: [
                for (final row in unique)
                  ListTile(
                    title: Text(
                      row['note'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${row['date']} · ${row['income'] == true ? 'Income' : 'Expense'}',
                    ),
                    trailing: Text(money(row['amount'])),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Import reviewed rows'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await act(
        () => store.mutate((state) {
          for (final row in unique) {
            if (row['income'] == true) {
              (state['incomeLog'] as List).add({
                'id': row['id'],
                'date': row['date'],
                'amount': row['amount'],
                'note': row['note'],
              });
              continue;
            }
            final note = row['note'].toString().toLowerCase();
            final rule = rows(state['rules'])
                .where(
                  (r) => note.contains(
                    r['match']?.toString().toLowerCase() ?? '\u0000',
                  ),
                )
                .firstOrNull;
            final category =
                rule?['categoryId'] ??
                planner.categories
                    .where(
                      (c) => note.contains(c['name'].toString().toLowerCase()),
                    )
                    .firstOrNull?['id'] ??
                planner.categories.firstOrNull?['id'] ??
                '';
            (state['budget']['expenses'] as List).add({
              'id': row['id'],
              'date': row['date'],
              'amount': row['amount'],
              'note': row['note'],
              'categoryId': category,
              'src': 'import',
            });
          }
        }),
      );
      message('Imported ${unique.length} transactions.');
    } catch (failure) {
      message('Import failed: $failure');
    }
  }

  Future<void> recoverReceiptCapture() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (!mounted || lost.isEmpty) return;
      if (lost.files?.isNotEmpty == true)
        await reviewReceipt(lost.files!.first);
      else if (lost.exception != null)
        message('Receipt capture was interrupted. Please try again.');
    } catch (_) {
      /* Recovery must not block offline startup. */
    }
  }

  Future<void> scanReceipt() async {
    if (working) return;
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('Scan receipt'),
                style: Theme.of(c).textTheme.titleLarge,
              ),
            ),
            if (kIsWeb ||
                defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(tr('Take photo')),
                onTap: () => Navigator.pop(c, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Choose image')),
              onTap: () => Navigator.pop(c, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final XFile? file;
      if (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        file = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 2400,
          imageQuality: 90,
          requestFullMetadata: false,
        );
      } else {
        file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Receipt',
              extensions: ['png', 'jpg', 'jpeg', 'webp'],
            ),
          ],
        );
      }
      if (file != null && mounted) await reviewReceipt(file);
    } catch (failure) {
      message(
        'Camera or image selection failed. Try choosing a saved receipt image. $failure',
      );
    }
  }

  Future<void> reviewReceipt(XFile file) async {
    try {
      if (await file.length() > 20 * 1024 * 1024)
        throw const FormatException('Receipt image exceeds 20 MB.');
      String? recognized;
      await act(() async {
        recognized = await recognizeReceipt(file);
      });
      if (recognized == null || !mounted) return;
      final amount = RegExp(
        r'(?:grand\s*total|total|amount\s*paid)\s*[:\-]?\s*(?:Rs\.?|INR|₹|\$)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ).firstMatch(recognized!)?.group(1);
      final value = await editRecord(
        context,
        'Review receipt',
        expenseFields,
        record: {
          'id': newId(),
          'amount': parseAmount(amount ?? '') ?? 0,
          'date': importDate(recognized!) ?? planner.today,
          'categoryId': categoryChoices.keys.firstOrNull ?? '',
          'note': file.name,
          'src': 'receipt',
        },
      );
      if (value != null) await act(() => store.put('budget.expenses', value));
    } catch (failure) {
      message('Receipt could not be read: $failure');
    }
  }

  Future<void> splitLocalBill() async {
    final value = await editRecord(context, 'Split a bill', [
      const Field('note', 'Bill description'),
      const Field(
        'mode',
        'Split method',
        choices: {'equal': 'Equal shares', 'items': 'Assign items'},
      ),
      const Field(
        'total',
        'Bill total (equal split)',
        numeric: true,
        required: false,
      ),
      const Field('names', 'Friends (comma separated, excluding you)'),
      const Field(
        'items',
        'Items: Item | Amount | You, Friend (one per line)',
        required: false,
        lines: 5,
      ),
      const Field(
        'charges',
        'Tax / service charges (item split)',
        numeric: true,
        required: false,
      ),
      Field('categoryId', 'Your budget category', choices: categoryChoices),
    ]);
    if (value == null) return;
    final names = (value['names'] as String)
        .split(',')
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    if (names.any((n) => n.toLowerCase() == 'you')) {
      message('Use You only for your own share.');
      return;
    }
    final total = (number(value['total']) * 100).round();
    if (names.isEmpty || (value['mode'] != 'items' && total <= 0)) {
      message('Enter a positive bill and at least one friend.');
      return;
    }
    final people = ['You', ...names];
    late Map<String, int> shares;
    try {
      shares = value['mode'] == 'items'
          ? itemizedShares(
              people,
              value['items'] ?? '',
              charges: (number(value['charges']) * 100).round(),
            )
          : {
              for (var i = 0; i < people.length; i++)
                people[i]:
                    total ~/ people.length +
                    (i < total % people.length ? 1 : 0),
            };
    } catch (error) {
      message(error.toString());
      return;
    }
    if (!mounted ||
        !await confirm(
          context,
          'Save bill split?',
          shares.entries
              .map((e) => '${e.key}: ${money(e.value / 100)}')
              .join('\n'),
        ))
      return;
    final mine = shares['You']!;
    final splitId = newId();
    await act(
      () => store.mutate((s) {
        (s['budget']['expenses'] as List).add({
          'id': newId(),
          'amount': mine / 100,
          'categoryId': value['categoryId'],
          'note': value['note'],
          'date': planner.today,
          'splitId': splitId,
        });
        for (var i = 0; i < names.length; i++)
          (s['wallet']['ious'] as List).add({
            'id': newId(),
            'person': names[i],
            'dir': 'owed',
            'amount': shares[names[i]]! / 100,
            'date': planner.today,
            'note': value['note'],
            'settled': false,
            'splitId': splitId,
          });
      }),
    );
  }

  Future<void> upiSettlement(Json iou) async {
    if (state['currency'] != 'INR') {
      message('UPI settlement is available only for INR records.');
      return;
    }
    final isRequest = iou['dir'] == 'owed';
    final value = await editRecord(
      context,
      isRequest ? 'Request UPI settlement' : 'Pay with UPI',
      const [Field('upi', 'Recipient UPI ID'), Field('name', 'Recipient name')],
      record: {
        'upi': isRequest
            ? state['settings']['myUpiId'] ?? ''
            : iou['upi'] ??
                  (state['wallet']['upiIds'] as Map?)?[iou['person']] ??
                  '',
        'name': isRequest ? 'HEIST' : iou['person'],
      },
    );
    if (value == null || !mounted) return;
    final id = (value['upi'] as String).trim();
    if (!RegExp(r'^[A-Za-z0-9._-]{2,256}@[A-Za-z]{2,64}$').hasMatch(id)) {
      message('Enter a valid UPI ID.');
      return;
    }
    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': id,
        'pn': value['name'],
        'am': number(iou['amount']).toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'HEIST settlement',
      },
    );
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          isRequest
              ? 'Share this payment request'
              : 'Review recipient before paying',
        ),
        content: SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: uri.toString(), size: 230),
                ),
                SelectableText(
                  '${value['name']}\n$id\nINR ${number(iou['amount']).toStringAsFixed(2)}',
                ),
                const Text(
                  'Opening UPI does not mark the IOU paid. Record settlement only after confirming receipt.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('Close')),
          ),
          if (!isRequest)
            FilledButton(
              onPressed: () async {
                if (!await launchUrl(uri, mode: LaunchMode.externalApplication))
                  message('No UPI application could open this payment link.');
              },
              child: const Text('Open UPI app'),
            ),
        ],
      ),
    );
  }
}
