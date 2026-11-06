import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/core/l10n/l10n.dart';

/// Every tr('...') key in the app has an Urdu entry with the same placeholders.
void main() {
  // tr('...') / tr("...") literal keys, and the word forms passed to plural().
  final trCall = RegExp(r"""\btr\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""");
  final pluralCall = RegExp(r"""\bplural\([^,]+,\s*'([^']*)'(?:\s*,\s*'([^']*)')?\)""");
  final placeholder = RegExp(r'\{(\w+)\}');

  Map<String, String> keysInCode() {
    final keys = <String, String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.contains('core/l10n/'))) {
      final src = f.readAsStringSync();
      for (final m in trCall.allMatches(src)) {
        keys[(m.group(1) ?? m.group(2))!.replaceAll(r"\'", "'").replaceAll(r'\"', '"').replaceAll(r'\n', '\n')] = f.path;
      }
      for (final m in pluralCall.allMatches(src)) {
        keys[m.group(1)!] = f.path;
        keys[m.group(2) ?? '${m.group(1)}s'] = f.path;
      }
    }
    return keys..removeWhere((k, _) => k.contains(r'$')); // interpolated keys can't be checked statically
  }

  test('every translated text has Urdu', () {
    final missing = [
      for (final e in keysInCode().entries)
        if (!L10n.urdu.containsKey(e.key)) '${e.value}: ${e.key}',
    ];
    expect(missing, isEmpty, reason: 'No Urdu for:\n${missing.join('\n')}');
  });

  test('Urdu keeps the same placeholders', () {
    final bad = [
      for (final e in L10n.urdu.entries)
        if ({...placeholder.allMatches(e.key).map((m) => m[1])}.difference({...placeholder.allMatches(e.value).map((m) => m[1])}).isNotEmpty) e.key,
    ];
    expect(bad, isEmpty, reason: 'Placeholders differ for:\n${bad.join('\n')}');
  });

  test('tr fills placeholders and falls back to English', () {
    L10n.lang.value = 'ur';
    addTearDown(() => L10n.lang.value = 'en');
    expect(tr('{n} min', {'n': 5}), '5 منٹ');
    expect(tr('Text that has no Urdu yet'), 'Text that has no Urdu yet');
  });
}
