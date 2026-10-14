import 'package:flutter/material.dart';

import 'api_client.dart';
import 'models.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({required this.onAuthenticated, super.key});

  final void Function(ApiClient client, SessionUser user) onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController(text: 'http://10.0.2.2:5180');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _cpf = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _name.dispose();
    _email.dispose();
    _cpf.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obrigatório' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    ApiClient? client;
    try {
      client = ApiClient(_server.text);
      if (_registering) {
        await client.registerStudent(
          name: _name.text,
          email: _email.text,
          username: _username.text,
          password: _password.text,
          cpf: _cpf.text,
        );
        client.dispose();
        client = null;
        if (!mounted) return;
        setState(() {
          _registering = false;
          _password.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cadastro realizado. Agora entre na sua conta.')),
        );
      } else {
        final user = await client.login(_username.text.trim(), _password.text);
        if (!mounted) {
          client.dispose();
          return;
        }
        widget.onAuthenticated(client, user);
        client = null;
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Ocorreu um erro inesperado.');
    } finally {
      client?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.local_library_outlined, size: 52),
                          const SizedBox(height: 12),
                          Text(
                            _registering
                                ? 'Cadastro de aluno'
                                : 'Biblioteca Mobile',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _registering
                                ? 'Crie sua conta de leitor.'
                                : 'Entre para acessar seus empréstimos.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _server,
                            decoration: const InputDecoration(
                              labelText: 'Endereço do servidor',
                              prefixIcon: Icon(Icons.dns_outlined),
                              helperText: 'Emulador: http://10.0.2.2:5180',
                            ),
                            keyboardType: TextInputType.url,
                            validator: _required,
                          ),
                          if (_registering) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _name,
                              decoration: const InputDecoration(
                                labelText: 'Nome completo',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: _required,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _email,
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                final requiredMessage = _required(value);
                                if (requiredMessage != null)
                                  return requiredMessage;
                                return value!.contains('@')
                                    ? null
                                    : 'Informe um e-mail válido';
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _cpf,
                              decoration: const InputDecoration(
                                labelText: 'CPF (opcional)',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ],
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _username,
                            decoration: const InputDecoration(
                              labelText: 'Usuário',
                              prefixIcon: Icon(Icons.account_circle_outlined),
                            ),
                            validator: _required,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _hidePassword,
                            decoration: InputDecoration(
                              labelText: 'Senha',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                    () => _hidePassword = !_hidePassword),
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              final requiredMessage = _required(value);
                              if (requiredMessage != null)
                                return requiredMessage;
                              if (_registering && value!.length < 8) {
                                return 'Use pelo menos 8 caracteres';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _busy ? null : _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _busy ? null : _submit,
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(_registering
                                    ? Icons.person_add_alt_1
                                    : Icons.login),
                            label:
                                Text(_registering ? 'Criar conta' : 'Entrar'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _registering = !_registering;
                                      _error = null;
                                    }),
                            child: Text(
                              _registering
                                  ? 'Já tenho conta'
                                  : 'Ainda não tenho cadastro',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
