import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({required this.client, super.key});

  final ApiClient client;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _books = [];
  bool _loading = true;
  final Set<int> _loadingBookIds = <int>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.books(query: _search.text);
      final rawItems = response['items'];
      final items = rawItems is List
          ? rawItems.whereType<Map<String, dynamic>>().toList(growable: false)
          : <Map<String, dynamic>>[];
      if (mounted) setState(() => _books = items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCopies(Map<String, dynamic> book) async {
    final bookId = (book['idLivro'] as num?)?.toInt();
    if (bookId == null || _loadingBookIds.contains(bookId)) return;
    setState(() => _loadingBookIds.add(bookId));
    try {
      final response = await widget.client.copiesForBook(bookId);
      final rawItems = response['items'];
      final copies = rawItems is List
          ? rawItems.whereType<Map<String, dynamic>>().toList(growable: false)
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${book['titulo'] ?? 'Livro'}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                const Text('Códigos dos exemplares'),
                const SizedBox(height: 14),
                if (copies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Este livro ainda não possui exemplares cadastrados.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: copies.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final copy = copies[index];
                        final code = '${copy['codigoTombo'] ?? 'Sem código'}';
                        final status = '${copy['situacao'] ?? '—'}';
                        final available = status == 'DISPONIVEL';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            available
                                ? Icons.check_circle_outline
                                : Icons.bookmark_added_outlined,
                            color: available
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: SelectableText(
                            code,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            available ? 'Disponível para empréstimo' : status,
                          ),
                          trailing: IconButton(
                            tooltip: 'Copiar código',
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: code));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Código $code copiado.')),
                              );
                            },
                            icon: const Icon(Icons.copy_outlined),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingBookIds.remove(bookId));
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text('Catálogo', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Consulte os livros disponíveis na biblioteca.'),
            const SizedBox(height: 16),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Buscar título ou ISBN',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    onPressed: _load, icon: const Icon(Icons.arrow_forward)),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()))
            else if (_error != null)
              _Message(message: _error!, action: _load)
            else if (_books.isEmpty)
              const _Message(message: 'Nenhum livro encontrado.')
            else
              ..._books.map((book) {
                final bookId = (book['idLivro'] as num?)?.toInt();
                final available = (book['disponiveis'] as num?)?.toInt() ?? 0;
                final loadingCopies =
                    bookId != null && _loadingBookIds.contains(bookId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        child: Text('${book['titulo'] ?? '?'}'
                            .substring(0, 1)
                            .toUpperCase()),
                      ),
                      title: Text(
                        '${book['titulo'] ?? 'Sem título'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${book['editora'] ?? 'Editora não informada'} • ${book['anoPublicacao'] ?? '—'}\n'
                              '${book['categoria'] ?? 'Sem categoria'}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Toque para ver os códigos dos exemplares',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: loadingCopies
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Chip(
                              avatar: Icon(
                                available > 0
                                    ? Icons.check_circle_outline
                                    : Icons.block,
                                size: 18,
                              ),
                              label: Text('$available'),
                            ),
                      onTap: loadingCopies ? null : () => _showCopies(book),
                    ),
                  ),
                );
              }),
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.message, this.action});

  final String message;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.info_outline, size: 40),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (action != null)
              TextButton(
                  onPressed: action, child: const Text('Tentar novamente')),
          ],
        ),
      );
}
