import 'package:material_ui/material_ui.dart';
import '../domain/planner.dart';
import 'translations.dart';

class Field {
  final String key, label;
  final bool numeric, date, required;
  final double? max;
  final bool obscure;
  final int lines;
  final Map<String, String>? choices;
  const Field(
    this.key,
    this.label, {
    this.numeric = false,
    this.date = false,
    this.required = true,
    this.max,
    this.choices,
    this.obscure = false,
    this.lines = 1,
  });
}

Future<Json?> editRecord(
  BuildContext context,
  String title,
  List<Field> fields, {
  Json? record,
}) async {
  final form = GlobalKey<FormState>();
  final controls = {
    for (final f in fields)
      f.key: TextEditingController(
        text:
            (record?[f.key] ??
                    (f.date
                        ? isoDate(DateTime.now())
                        : f.choices?.keys.firstOrNull ?? ''))
                .toString(),
      ),
  };
  final result = await showDialog<Json>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        translate(Localizations.localeOf(context).languageCode, title),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: f.choices != null
                        ? DropdownButtonFormField<String>(
                            initialValue:
                                f.choices!.containsKey(controls[f.key]!.text)
                                ? controls[f.key]!.text
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: translate(
                                Localizations.localeOf(context).languageCode,
                                f.label,
                              ),
                            ),
                            items: f.choices!.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                controls[f.key]!.text = value ?? '',
                            validator: (v) =>
                                f.required && (v == null || v.isEmpty)
                                ? 'Choose ${f.label.toLowerCase()}.'
                                : null,
                          )
                        : TextFormField(
                            obscureText: f.obscure,
                            minLines: f.obscure ? 1 : f.lines,
                            maxLines: f.obscure ? 1 : f.lines,
                            autocorrect: !f.obscure,
                            enableSuggestions: !f.obscure,
                            controller: controls[f.key],
                            decoration: InputDecoration(
                              labelText: translate(
                                Localizations.localeOf(context).languageCode,
                                f.label,
                              ),
                              hintText: f.date ? 'YYYY-MM-DD' : null,
                            ),
                            keyboardType: f.numeric
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : TextInputType.text,
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty)
                                return f.required ? 'Required.' : null;
                              if (f.numeric) {
                                final n = double.tryParse(value!);
                                if (n == null ||
                                    !n.isFinite ||
                                    n < 0 ||
                                    (f.max != null && n > f.max!))
                                  return 'Enter a valid nonnegative number${f.max != null ? ' up to ${f.max}' : ''}.';
                              }
                              if (f.date && !validDate(value!))
                                return 'Use a valid YYYY-MM-DD date.';
                              return null;
                            },
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            translate(Localizations.localeOf(context).languageCode, 'Cancel'),
          ),
        ),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            final next = <String, dynamic>{
              ...?record,
              'id': record?['id'] ?? newId(),
            };
            for (final f in fields) {
              final text = controls[f.key]!.text.trim();
              next[f.key] = f.numeric ? double.tryParse(text) ?? 0 : text;
            }
            Navigator.pop(context, next);
          },
          child: Text(
            translate(Localizations.localeOf(context).languageCode, 'Save'),
          ),
        ),
      ],
    ),
  );
  // Controllers are retained by the closing route during its exit animation.
  Future<void>.delayed(const Duration(seconds: 1), () {
    for (final c in controls.values) {
      c.dispose();
    }
  });
  return result;
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          translate(Localizations.localeOf(context).languageCode, title),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              translate(Localizations.localeOf(context).languageCode, 'Cancel'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;
