import 'package:flutter/material.dart';

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Minúsculas e sem acentos, para busca tolerante ("joao" encontra "João").
String normalizeSearch(String text) {
  final lower = text.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final ch in lower.split('')) {
    buffer.write(_accents[ch] ?? ch);
  }
  return buffer.toString();
}

/// Verdadeiro quando todas as palavras da busca aparecem em algum campo.
/// Números (CPF/telefone) também são comparados só pelos dígitos.
bool matchesSearch(String query, Iterable<String?> fields) {
  final q = normalizeSearch(query);
  if (q.isEmpty) return true;
  final haystack =
      normalizeSearch(fields.whereType<String>().join(' | '));
  final digits = haystack.replaceAll(RegExp(r'\D'), '');
  return q.split(RegExp(r'\s+')).every((word) {
    if (haystack.contains(word)) return true;
    final wordDigits = word.replaceAll(RegExp(r'\D'), '');
    return wordDigits.length >= 3 &&
        wordDigits == word.replaceAll(RegExp(r'[.\-/() ]'), '') &&
        digits.contains(wordDigits);
  });
}

/// Barra de pesquisa com botão de limpar.
class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final EdgeInsetsGeometry padding;

  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 4),
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}
