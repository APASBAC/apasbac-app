/// Busca todas as páginas de uma listagem da API (máximo de 100 por página),
/// parando quando uma página vem incompleta.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int page, int limit) load, {
  int limit = 100,
  int maxPages = 50,
}) async {
  final all = <T>[];
  for (var page = 1; page <= maxPages; page++) {
    final items = await load(page, limit);
    all.addAll(items);
    if (items.length < limit) break;
  }
  return all;
}
