import 'package:flutter/material.dart';

import 'api_client.dart';
import 'models.dart';

class LoansPage extends StatefulWidget {
  const LoansPage({required this.client, super.key});

  final ApiClient client;

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  List<Map<String, dynamic>> _loans = [];
  String? _status = 'ABERTO';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.client.myLoans(status: _status);
      final rawItems = response['items'];
      final items = rawItems is List
          ? rawItems.whereType<Map<String, dynamic>>().toList(growable: false)
          : <Map<String, dynamic>>[];
      if (mounted) setState(() => _loans = items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text('Meus empréstimos',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Acompanhe prazos e devoluções.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Situação',
                prefixIcon: Icon(Icons.filter_list),
              ),
              items: const [
                DropdownMenuItem(value: 'ABERTO', child: Text('Em aberto')),
                DropdownMenuItem(
                    value: 'FINALIZADO', child: Text('Finalizados')),
                DropdownMenuItem(value: null, child: Text('Todos')),
              ],
              onChanged: (value) {
                _status = value;
                _load();
              },
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()))
            else if (_error != null)
              _LoansMessage(message: _error!, action: _load)
            else if (_loans.isEmpty)
              const _LoansMessage(message: 'Nenhum empréstimo nesta situação.')
            else
              ..._loans.map((loan) {
                final overdue = loan['atrasado'] == true;
                final pending = (loan['itensPendentes'] as num?)?.toInt() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: overdue
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(overdue
                            ? Icons.warning_amber
                            : Icons.receipt_long_outlined),
                      ),
                      title: Text(
                        'Empréstimo #${loan['idEmprestimo'] ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Retirada: ${formatDate(loan['dataHoraEmprestimo'])}\n'
                          'Prazo: ${formatDate(loan['dataHoraPrevista'])} • $pending pendente(s)',
                        ),
                      ),
                      isThreeLine: true,
                      trailing: Chip(
                        label: Text(
                            overdue ? 'ATRASADO' : '${loan['situacao'] ?? ''}'),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      );
}

class _LoansMessage extends StatelessWidget {
  const _LoansMessage({required this.message, this.action});

  final String message;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.history, size: 40),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (action != null)
              TextButton(
                  onPressed: action, child: const Text('Tentar novamente')),
          ],
        ),
      );
}
