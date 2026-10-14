import 'package:flutter/material.dart';

import 'api_client.dart';
import 'models.dart';

enum CheckoutMode { loan, returnBook }

class SelfCheckoutPage extends StatefulWidget {
  const SelfCheckoutPage({required this.client, super.key});

  final ApiClient client;

  @override
  State<SelfCheckoutPage> createState() => _SelfCheckoutPageState();
}

class _SelfCheckoutPageState extends State<SelfCheckoutPage> {
  final _code = TextEditingController();
  final List<SelectedCopy> _copies = [];
  CheckoutMode _mode = CheckoutMode.loan;
  bool _finding = false;
  bool _confirming = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _action => _mode == CheckoutMode.loan ? 'empréstimo' : 'devolução';

  Future<void> _add() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    if (_copies.any((copy) => copy.code.toLowerCase() == code.toLowerCase())) {
      setState(() => _error = 'Esse exemplar já foi adicionado.');
      return;
    }
    setState(() {
      _finding = true;
      _error = null;
    });
    try {
      final copy = await widget.client.findCopy(code);
      final expected = _mode == CheckoutMode.loan ? 'DISPONIVEL' : 'EMPRESTADO';
      if (copy.status != expected) {
        throw ApiException(
          _mode == CheckoutMode.loan
              ? 'Este exemplar não está disponível para empréstimo.'
              : 'Este exemplar não está marcado como emprestado.',
        );
      }
      if (!mounted) return;
      setState(() {
        _copies.add(copy);
        _code.clear();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  Future<void> _confirm() async {
    if (_copies.isEmpty) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final codes = _copies.map((copy) => copy.code).toList(growable: false);
      if (_mode == CheckoutMode.loan) {
        await widget.client.checkout(codes);
      } else {
        await widget.client.returnCopies(codes);
      }
      if (!mounted) return;
      setState(_copies.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${_action[0].toUpperCase()}${_action.substring(1)} confirmado!')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _changeMode(CheckoutMode mode) {
    if (_confirming) return;
    setState(() {
      _mode = mode;
      _copies.clear();
      _error = null;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Self-checkout',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Digite o código impresso no exemplar.'),
          const SizedBox(height: 16),
          SegmentedButton<CheckoutMode>(
            segments: const [
              ButtonSegment(
                value: CheckoutMode.loan,
                icon: Icon(Icons.shopping_bag_outlined),
                label: Text('Emprestar'),
              ),
              ButtonSegment(
                value: CheckoutMode.returnBook,
                icon: Icon(Icons.assignment_return_outlined),
                label: Text('Devolver'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => _changeMode(selection.first),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _code,
                    enabled: !_confirming,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Código do exemplar',
                      hintText: 'Ex.: DEMO-BD-001',
                      prefixIcon: const Icon(Icons.qr_code_2),
                      suffixIcon: IconButton(
                        onPressed: _finding ? null : _add,
                        icon: _finding
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_circle_outline),
                      ),
                    ),
                    onSubmitted: (_) => _finding ? null : _add(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.menu_book_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _mode == CheckoutMode.loan
                              ? 'Exemplares para emprestar'
                              : 'Exemplares para devolver',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Badge(label: Text('${_copies.length}')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_copies.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'Nenhum exemplar adicionado ainda.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    ..._copies.map(
                      (copy) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.book_outlined),
                        title: Text(copy.title),
                        subtitle: Text(copy.code),
                        trailing: IconButton(
                          tooltip: 'Remover',
                          onPressed: _confirming
                              ? null
                              : () => setState(() => _copies.remove(copy)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _copies.isEmpty || _confirming ? null : _confirm,
                    icon: _confirming
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                        _confirming ? 'Confirmando...' : 'Confirmar $_action'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}
