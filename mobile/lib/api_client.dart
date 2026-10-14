import 'dart:convert';
import 'dart:io';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(String baseUrl)
      : baseUrl = _normalizeBaseUrl(baseUrl),
        _http = HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 12);
  }

  final String baseUrl;
  final HttpClient _http;
  String? _token;

  bool get isAuthenticated => _token != null;

  static String _normalizeBaseUrl(String value) {
    var normalized = value.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ApiException(
          'Informe um endereço válido, como http://192.168.0.10:5180.');
    }
    return normalized;
  }

  Future<SessionUser> login(String username, String password) async {
    final data = await _request(
      'POST',
      '/api/v1/auth/login',
      body: <String, Object?>{'username': username, 'senha': password},
      authenticated: false,
    ) as Map<String, dynamic>;
    _token = data['accessToken'] as String?;
    final user = data['usuario'];
    if (_token == null || user is! Map<String, dynamic>) {
      throw const ApiException('Resposta de login inválida.');
    }
    return SessionUser.fromJson(user);
  }

  Future<void> registerStudent({
    required String name,
    required String email,
    required String username,
    required String password,
    String? cpf,
  }) async {
    await _request(
      'POST',
      '/api/v1/auth/cadastro-aluno',
      body: <String, Object?>{
        'nome': name,
        'email': email,
        'username': username,
        'senha': password,
        'cpf': cpf == null || cpf.trim().isEmpty ? null : cpf.trim(),
      },
      authenticated: false,
    );
  }

  Future<SelectedCopy> findCopy(String code) async {
    final data = await _request(
      'GET',
      '/api/v1/exemplares/codigo/${Uri.encodeComponent(code)}',
    ) as Map<String, dynamic>;
    return SelectedCopy.fromJson(data);
  }

  Future<Map<String, dynamic>> checkout(List<String> codes) async =>
      await _request(
        'POST',
        '/api/v1/self-checkout/emprestimos',
        body: <String, Object?>{'codigosExemplares': codes},
      ) as Map<String, dynamic>;

  Future<Map<String, dynamic>> returnCopies(List<String> codes) async =>
      await _request(
        'POST',
        '/api/v1/self-checkout/devolucoes',
        body: <String, Object?>{'codigosExemplares': codes},
      ) as Map<String, dynamic>;

  Future<Map<String, dynamic>> books({String? query, int page = 1}) async {
    final parameters = <String, String>{'page': '$page', 'pageSize': '30'};
    if (query != null && query.trim().isNotEmpty)
      parameters['q'] = query.trim();
    return await _request('GET', '/api/v1/livros', query: parameters)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> copiesForBook(int bookId) async =>
      await _request(
        'GET',
        '/api/v1/exemplares',
        query: <String, String>{
          'idLivro': '$bookId',
          'page': '1',
          'pageSize': '100',
        },
      ) as Map<String, dynamic>;

  Future<Map<String, dynamic>> myLoans({String? status, int page = 1}) async {
    final parameters = <String, String>{'page': '$page', 'pageSize': '30'};
    if (status != null && status.isNotEmpty) parameters['situacao'] = status;
    return await _request('GET', '/api/v1/me/emprestimos', query: parameters)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loan(int id) async =>
      await _request('GET', '/api/v1/emprestimos/$id') as Map<String, dynamic>;

  void logout() => _token = null;

  void dispose() {
    _http.close(force: true);
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool authenticated = true,
  }) async {
    if (authenticated && _token == null) {
      throw const ApiException('Sua sessão terminou. Entre novamente.',
          statusCode: 401);
    }

    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    try {
      final request = await _http.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      if (authenticated) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (body != null) request.write(jsonEncode(body));

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      Object? decoded;
      if (text.trim().isNotEmpty) {
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          decoded = text;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var message = 'Não foi possível concluir a operação.';
        if (decoded is Map<String, dynamic>) {
          message = decoded['detail'] as String? ??
              decoded['title'] as String? ??
              message;
        } else if (decoded is String && decoded.trim().isNotEmpty) {
          final plainText =
              decoded.replaceAll(RegExp('<[^>]*>'), ' ').replaceAll(
                    RegExp(r'\s+'),
                    ' ',
                  );
          if (plainText.toLowerCase().contains('invalid hostname')) {
            message =
                'O servidor recusou o endereço do emulador. Reinicie a Biblioteca com a versão atualizada.';
          } else if (!decoded.trimLeft().startsWith('<')) {
            message = decoded;
          }
        }
        throw ApiException(message, statusCode: response.statusCode);
      }
      return decoded ?? <String, dynamic>{};
    } on SocketException {
      throw ApiException(
        'Não foi possível acessar $baseUrl. Confirme o endereço, o Wi-Fi e se o servidor está aberto para a rede local.',
      );
    } on HttpException catch (error) {
      throw ApiException('Falha de comunicação: ${error.message}');
    }
  }
}
