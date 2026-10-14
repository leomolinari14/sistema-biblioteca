import 'package:flutter/material.dart';

import 'api_client.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BibliotecaMobileApp());
}

class BibliotecaMobileApp extends StatelessWidget {
  const BibliotecaMobileApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Biblioteca Mobile',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF185ABD),
            primary: const Color(0xFF185ABD),
            secondary: const Color(0xFF0E9F6E),
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FB),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              side: BorderSide(color: Color(0xFFE0E5ED)),
            ),
          ),
        ),
        home: const SessionGate(),
      );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  ApiClient? _client;
  SessionUser? _user;

  void _onAuthenticated(ApiClient client, SessionUser user) {
    setState(() {
      _client = client;
      _user = user;
    });
  }

  void _logout() {
    _client?.logout();
    _client?.dispose();
    setState(() {
      _client = null;
      _user = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final user = _user;
    if (client == null || user == null) {
      return LoginPage(onAuthenticated: _onAuthenticated);
    }
    return HomePage(client: client, user: user, onLogout: _logout);
  }
}
