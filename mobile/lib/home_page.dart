import 'package:flutter/material.dart';

import 'api_client.dart';
import 'catalog_page.dart';
import 'loans_page.dart';
import 'models.dart';
import 'self_checkout_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.client,
    required this.user,
    required this.onLogout,
    super.key,
  });

  final ApiClient client;
  final SessionUser user;
  final VoidCallback onLogout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  late final List<Widget> _pages = [
    SelfCheckoutPage(client: widget.client),
    LoansPage(client: widget.client),
    CatalogPage(client: widget.client),
    _ProfilePage(
      user: widget.user,
      server: widget.client.baseUrl,
      onLogout: widget.onLogout,
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Biblioteca'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: Text(widget.user.name.split(' ').first)),
            ),
          ],
        ),
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_outlined),
              selectedIcon: Icon(Icons.qr_code_scanner),
              label: 'Checkout',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Empréstimos',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Catálogo',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      );
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.user,
    required this.server,
    required this.onLogout,
  });

  final SessionUser user;
  final String server;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Meu perfil', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const CircleAvatar(
                      radius: 38, child: Icon(Icons.person, size: 40)),
                  const SizedBox(height: 12),
                  Text(
                    user.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  Text('@${user.username}'),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Perfil'),
                    subtitle: Text(user.profile == 'LEITOR'
                        ? 'Aluno / leitor'
                        : user.profile),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Servidor conectado'),
                    subtitle: Text(server),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sair'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}
