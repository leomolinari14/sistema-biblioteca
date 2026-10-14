"""Integration tests against a running Biblioteca API and a dedicated test database.

Uses only the Python standard library. Creates identifiable records and never
deletes existing data. Never run this suite against a production database.
"""

import argparse
import concurrent.futures
import datetime
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid


OPTIONS = None


class BibliotecaSmokeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base_url = OPTIONS.base_url.rstrip("/") + "/api/v1"
        cls.prefix = "smk" + uuid.uuid4().hex[:10]
        cls.counter = 0
        cls.secrets = [OPTIONS.admin_password]
        cls.admin_token = cls.login(OPTIONS.admin_username, OPTIONS.admin_password)
        cls.configuration = cls.expect("GET", "/configuracoes", 200, token=cls.admin_token)
        cls.category_id = cls.expect(
            "POST", "/categorias", 201,
            {"nome": cls.prefix + " categoria", "descricao": "Teste HTTP automatizado"},
            cls.admin_token,
        )["idCategoria"]
        cls.publisher_id = cls.expect(
            "POST", "/editoras", 201,
            {"nome": cls.prefix + " editora", "nacionalidade": "Brasil"},
            cls.admin_token,
        )["idEditora"]
        cls.author_id = cls.expect(
            "POST", "/autores", 201,
            {"nome": cls.prefix + " autor", "nacionalidade": "Brasil"},
            cls.admin_token,
        )["idAutor"]

    @classmethod
    def redact(cls, value):
        result = str(value)
        for secret in cls.secrets:
            if secret:
                result = result.replace(secret, "[REDACTED]")
        return result

    @classmethod
    def request(cls, method, path, body=None, token=None):
        headers = {"Accept": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        if body is not None:
            headers["Content-Type"] = "application/json"
        data = None if body is None else json.dumps(body).encode("utf-8")
        request = urllib.request.Request(cls.base_url + path, data, headers, method=method)
        try:
            response = urllib.request.urlopen(request, timeout=OPTIONS.timeout)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            status = response.code
            raw = response.read().decode("utf-8-sig")
            try:
                parsed = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                parsed = {"detail": cls.redact(raw[:500])}
            return status, parsed

    @classmethod
    def expect(cls, method, path, expected, body=None, token=None):
        status, parsed = cls.request(method, path, body, token)
        accepted = (expected,) if isinstance(expected, int) else expected
        if status not in accepted:
            # A successful login body contains a token and must not be printed.
            detail = "resposta de autenticacao omitida" if path == "/auth/login" else cls.redact(parsed)
            raise AssertionError(
                f"{method} {path}: esperado {accepted}; recebido {status}; {detail}"
            )
        return parsed

    @classmethod
    def login(cls, username, password):
        data = cls.expect("POST", "/auth/login", 200, {"username": username, "senha": password})
        token = data.get("accessToken")
        if not isinstance(token, str) or not token:
            raise AssertionError("O login nao retornou accessToken valido.")
        cls.secrets.append(token)
        return token

    @classmethod
    def next_name(cls, suffix):
        cls.counter += 1
        return f"{cls.prefix}_{suffix}{cls.counter}"

    @classmethod
    def reader(cls):
        username = cls.next_name("leitor")
        password = "T3ste!" + secrets.token_hex(14)
        cls.secrets.append(password)
        user = cls.expect(
            "POST", "/usuarios", 201,
            {
                "nome": "Leitor de teste " + username,
                "email": username + "@example.invalid",
                "username": username,
                "senha": password,
                "perfil": "LEITOR",
            },
            cls.admin_token,
        )
        return user["idUsuario"], cls.login(username, password)

    @classmethod
    def copies(cls, quantity=1):
        book = cls.expect(
            "POST", "/livros", 201,
            {
                "titulo": cls.next_name("livro"),
                "idEditora": cls.publisher_id,
                "idCategoria": cls.category_id,
                "anoPublicacao": 2026,
                "numeroEdicao": 1,
                "idsAutores": [cls.author_id],
            },
            cls.admin_token,
        )
        result = []
        for _ in range(quantity):
            code = cls.next_name("tombo")
            copy = cls.expect(
                "POST", "/exemplares", 201,
                {
                    "idLivro": book["idLivro"],
                    "codigoTombo": code,
                    "dataAquisicao": datetime.date.today().isoformat(),
                },
                cls.admin_token,
            )
            result.append({"idExemplar": copy["idExemplar"], "codigoTombo": code})
        return result

    @classmethod
    def checkout(cls, token, copies, expected=201, **extra):
        body = {"codigosExemplares": [copy["codigoTombo"] for copy in copies], **extra}
        return cls.expect("POST", "/self-checkout/emprestimos", expected, body, token)

    @classmethod
    def return_copies(cls, loan_id, copies):
        return cls.expect(
            "POST", f"/emprestimos/{loan_id}/devolucoes", 200,
            {"idsExemplares": [copy["idExemplar"] for copy in copies]}, cls.admin_token,
        )

    @classmethod
    def configuration_payload(cls, **changes):
        names = ("limiteExemplares", "prazoDias", "bloquearAtrasados", "selfCheckoutHabilitado")
        return {**{name: cls.configuration[name] for name in names}, **changes}

    def my_loans(self, token):
        data = self.expect("GET", "/me/emprestimos?page=1&pageSize=100", 200, token=token)
        for field in ("items", "total", "page", "pageSize"):
            self.assertIn(field, data, f"Paginacao sem campo {field}.")
        self.assertIsInstance(data["items"], list)
        return data["items"]

    def test_00_authentication_required_and_invalid_credentials(self):
        self.expect("GET", "/me/emprestimos", 401)
        self.expect("POST", "/self-checkout/emprestimos", 401, {"codigosExemplares": ["sem-login"]})
        self.expect("POST", "/auth/login", 401, {"username": OPTIONS.admin_username, "senha": "incorreta-" + uuid.uuid4().hex})

    def test_01_reader_cannot_manage_catalog_users_settings_or_returns(self):
        reader_id, token = self.reader()
        self.expect("POST", "/editoras", 403, {"nome": self.next_name("proibida")}, token)
        self.expect("POST", "/usuarios", 403, {"nome": "Proibido", "email": "proibido@example.invalid", "username": self.next_name("proibido"), "senha": "NaoUsar123!", "perfil": "ADMIN"}, token)
        self.expect("PUT", "/configuracoes", 403, self.configuration_payload(), token)
        copies = self.copies()
        self.expect("POST", "/emprestimos", 403, {"idUsuario": reader_id, "codigosExemplares": [copies[0]["codigoTombo"]]}, token)
        loan = self.checkout(token, copies)
        self.expect("POST", f"/emprestimos/{loan['idEmprestimo']}/devolucoes", 403, {"idsExemplares": [copies[0]["idExemplar"]]}, token)
        self.return_copies(loan["idEmprestimo"], copies)

    def test_02_self_checkout_belongs_to_authenticated_reader(self):
        owner_id, owner_token = self.reader()
        other_id, other_token = self.reader()
        copies = self.copies()
        code = urllib.parse.quote(copies[0]["codigoTombo"], safe="")
        copy = self.expect("GET", "/exemplares/codigo/" + code, 200, token=owner_token)
        self.assertEqual(copy["idExemplar"], copies[0]["idExemplar"])
        # A client-supplied user ID must never redirect a self-checkout to another person.
        self.checkout(owner_token, copies, expected=400, idUsuario=other_id)
        self.assertEqual(self.my_loans(owner_token), [])
        self.assertEqual(self.my_loans(other_token), [])
        loan = self.checkout(owner_token, copies)
        loan_id = loan["idEmprestimo"]
        self.assertIn(loan_id, [item["idEmprestimo"] for item in self.my_loans(owner_token)])
        self.assertNotIn(loan_id, [item["idEmprestimo"] for item in self.my_loans(other_token)])
        owner_receipt = self.expect("GET", f"/emprestimos/{loan_id}", 200, token=owner_token)
        self.assertEqual(owner_receipt["idUsuario"], owner_id)
        self.expect("GET", f"/emprestimos/{loan_id}", 200, token=self.admin_token)
        self.expect("GET", f"/emprestimos/{loan_id}", 404, token=other_token)

    def test_03_unknown_and_duplicate_codes_do_not_create_partial_loans(self):
        _, token = self.reader()
        copies = self.copies(2)
        missing = {"codigoTombo": self.next_name("inexistente")}
        self.checkout(token, [copies[0], missing], expected=(400, 404, 422))
        self.assertEqual(self.my_loans(token), [])
        first = self.checkout(token, [copies[0]])
        self.return_copies(first["idEmprestimo"], [copies[0]])
        self.checkout(token, [copies[1], copies[1]], expected=(400, 422))
        self.checkout(token, [copies[1]])

    def test_04_already_loaned_copy_rolls_back_entire_request(self):
        _, first_token = self.reader()
        _, second_token = self.reader()
        copies = self.copies(2)
        self.checkout(first_token, [copies[0]])
        self.checkout(second_token, [copies[1], copies[0]], expected=409)
        self.assertEqual(self.my_loans(second_token), [])
        self.checkout(second_token, [copies[1]])

    def test_05_active_item_limit_counts_across_loans(self):
        _, token = self.reader()
        _, other_token = self.reader()
        copies = self.copies(4)
        self.checkout(token, copies, expected=422)
        self.assertEqual(self.my_loans(token), [])
        self.checkout(token, copies[:2])
        self.checkout(token, copies[2:3])
        self.checkout(token, copies[3:], expected=422)
        self.checkout(other_token, copies[3:])

    def test_06_concurrent_readers_cannot_borrow_the_same_copy(self):
        _, first_token = self.reader()
        _, second_token = self.reader()
        copies = self.copies()
        barrier = threading.Barrier(2)

        def try_checkout(token):
            barrier.wait(timeout=10)
            return self.request("POST", "/self-checkout/emprestimos", {"codigosExemplares": [copies[0]["codigoTombo"]]}, token)

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(try_checkout, token) for token in (first_token, second_token)]
            responses = [future.result(timeout=OPTIONS.timeout + 15) for future in futures]
        self.assertEqual(sorted(status for status, _ in responses), [201, 409], self.redact(responses))
        totals = [len(self.my_loans(token)) for token in (first_token, second_token)]
        self.assertEqual(sorted(totals), [0, 1])

    def test_07_partial_return_finishes_only_after_last_item_and_allows_reloan(self):
        _, token = self.reader()
        _, next_token = self.reader()
        copies = self.copies(2)
        loan = self.checkout(token, copies)
        partial = self.return_copies(loan["idEmprestimo"], copies[:1])
        self.assertEqual(partial["situacao"], "ABERTO")
        self.checkout(next_token, copies[:1])
        self.checkout(next_token, copies[1:], expected=409)
        finished = self.return_copies(loan["idEmprestimo"], copies[1:])
        self.assertEqual(finished["situacao"], "FINALIZADO")
        self.checkout(next_token, copies[1:])

    def test_08_disabled_self_checkout_can_be_reenabled(self):
        _, token = self.reader()
        copies = self.copies()
        try:
            self.expect("PUT", "/configuracoes", 200, self.configuration_payload(selfCheckoutHabilitado=False), self.admin_token)
            self.checkout(token, copies, expected=422)
            self.assertEqual(self.my_loans(token), [])
        finally:
            self.expect("PUT", "/configuracoes", 200, self.configuration_payload(), self.admin_token)
        self.checkout(token, copies)

    def test_09_disabling_user_invalidates_existing_access_token(self):
        user_id, token = self.reader()
        copies = self.copies()
        self.expect("PATCH", f"/usuarios/{user_id}/ativo", 204, {"ativo": False}, self.admin_token)
        self.expect("GET", "/me/emprestimos", 401, token=token)
        self.checkout(token, copies, expected=401)

    def test_10_initial_policy_matches_documented_defaults(self):
        self.assertEqual(self.configuration["limiteExemplares"], 3)
        self.assertEqual(self.configuration["prazoDias"], 14)
        self.assertIs(self.configuration["bloquearAtrasados"], True)
        self.assertIs(self.configuration["selfCheckoutHabilitado"], True)

    def test_11_receipt_has_utc_dates_and_no_password_hash(self):
        _, token = self.reader()
        loan = self.checkout(token, self.copies())
        self.assertTrue(loan['dataHoraEmprestimo'].endswith('Z'))
        self.assertTrue(loan['dataHoraPrevista'].endswith('Z'))
        start = datetime.datetime.fromisoformat(loan['dataHoraEmprestimo'].replace('Z', '+00:00'))
        end = datetime.datetime.fromisoformat(loan['dataHoraPrevista'].replace('Z', '+00:00'))
        self.assertEqual((end - start).days, 14)
        users = self.expect('GET', '/usuarios', 200, token=self.admin_token)
        self.assertNotIn('senhaHash', json.dumps(users))
        self.assertNotIn('senhaHash', json.dumps(self.expect('GET', '/auth/me', 200, token=token)))

    def test_12_catalog_update_rolls_back_if_author_does_not_exist(self):
        copies = self.copies()
        copy = self.expect('GET', '/exemplares/codigo/' + copies[0]['codigoTombo'], 200, token=self.admin_token)
        book_id = copy['idLivro']
        original = self.expect('GET', f'/livros/{book_id}', 200, token=self.admin_token)
        self.expect('PUT', f'/livros/{book_id}', 422, {
            'titulo': 'Nao deve ser gravado', 'idEditora': self.publisher_id,
            'idCategoria': self.category_id, 'anoPublicacao': 2026, 'numeroEdicao': 1,
            'idsAutores': [2147483647],
        }, self.admin_token)
        after = self.expect('GET', f'/livros/{book_id}', 200, token=self.admin_token)
        self.assertEqual(after['titulo'], original['titulo'])
        self.assertEqual(after['autores'], original['autores'])

    def test_13_returns_reject_foreign_and_already_returned_items(self):
        reader_id, token = self.reader()
        copies = self.copies(2)
        # Exerce também o empréstimo de balcão.
        loan = self.expect('POST', '/emprestimos', 201, {
            'idUsuario': reader_id, 'codigosExemplares': [copies[0]['codigoTombo']],
        }, self.admin_token)
        self.assertEqual(loan['canal'], 'BALCAO')
        self.expect('POST', f"/emprestimos/{loan['idEmprestimo']}/devolucoes", (400,404,409,422), {
            'idsExemplares': [copies[0]['idExemplar'], copies[1]['idExemplar']],
        }, self.admin_token)
        receipt = self.expect('GET', f"/emprestimos/{loan['idEmprestimo']}", 200, token=token)
        self.assertEqual(receipt['situacao'], 'ABERTO')
        self.assertIsNone(receipt['itens'][0]['dataHoraDevolucao'])
        self.return_copies(loan['idEmprestimo'], copies[:1])
        self.expect('POST', f"/emprestimos/{loan['idEmprestimo']}/devolucoes", 409, {
            'idsExemplares': [copies[0]['idExemplar']],
        }, self.admin_token)

    def test_14_overdue_reader_cannot_borrow_until_returning(self):
        database = os.environ.get('BIBLIOTECA_TEST_DATABASE', '')
        if not re.fullmatch(r'BibliotecaTest_[A-Za-z0-9_]+', database):
            self.skipTest('Cenário de atraso exige BIBLIOTECA_TEST_DATABASE isolado.')
        _, token = self.reader()
        copies = self.copies(2)
        loan = self.checkout(token, copies[:1])
        loan_id = int(loan['idEmprestimo'])
        sql = f'UPDATE dbo.EMPRESTIMOS SET DataHoraEmprestimo=DATEADD(day,-30,SYSUTCDATETIME()), DataHoraPrevista=DATEADD(day,-1,SYSUTCDATETIME()) WHERE IdEmprestimo={loan_id};'
        result = subprocess.run(['sqlcmd', '-S', os.environ.get('BIBLIOTECA_TEST_SERVER', r'.\SQLEXPRESS'),
            '-d', database, '-E', '-C', '-b', '-l', '10', '-t', '15', '-Q', sql], capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, 'Falha na preparação controlada do atraso no banco de testes.')
        self.checkout(token, copies[1:], expected=422)
        self.return_copies(loan_id, copies[:1])
        self.checkout(token, copies[1:])

    def test_15_maintenance_copy_is_unavailable_and_loan_state_is_protected(self):
        _, token = self.reader()
        copies = self.copies()
        copy_id = copies[0]['idExemplar']
        self.expect('PATCH', f'/exemplares/{copy_id}/situacao', 204, {'situacao':'MANUTENCAO'}, self.admin_token)
        self.checkout(token, copies, expected=409)
        self.expect('PATCH', f'/exemplares/{copy_id}/situacao', 204, {'situacao':'DISPONIVEL'}, self.admin_token)
        self.checkout(token, copies)
        self.expect('PATCH', f'/exemplares/{copy_id}/situacao', 409, {'situacao':'DISPONIVEL'}, self.admin_token)

    def test_16_openapi_contains_self_checkout_and_authorization(self):
        url = OPTIONS.base_url.rstrip('/') + '/openapi/v1.json'
        with urllib.request.urlopen(url, timeout=OPTIONS.timeout) as response:
            schema = json.load(response)
        self.assertIn('/api/v1/self-checkout/emprestimos', schema['paths'])
        self.assertIn('post', schema['paths']['/api/v1/self-checkout/emprestimos'])
        self.assertIn('Bearer', schema['components']['securitySchemes'])
        self.assertEqual(schema['paths']['/api/v1/self-checkout/emprestimos']['post']['security'], [{'Bearer': []}])
        self.assertIn('/api/v1/emprestimos/{id}/devolucoes', schema['paths'])

    def test_17_concurrent_requests_for_same_reader_cannot_exceed_limit(self):
        _, token = self.reader()
        copies = self.copies(4)
        self.checkout(token, copies[:2])
        barrier = threading.Barrier(2)
        def request_one(copy):
            barrier.wait(timeout=10)
            return self.request('POST', '/self-checkout/emprestimos',
                {'codigosExemplares':[copy['codigoTombo']]}, token)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(request_one, copies[2:]))
        self.assertEqual(sorted(status for status, _ in results), [201,422])
        self.assertEqual(sum(x['itensPendentes'] for x in self.my_loans(token)), 3)


def main():
    global OPTIONS
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:5180", help="URL da API sem /api/v1")
    parser.add_argument("--admin-username", default=os.environ.get("BIBLIOTECA_ADMIN_USERNAME", "admin"))
    parser.add_argument("--admin-password", default=os.environ.get("BIBLIOTECA_ADMIN_PASSWORD"), help="Prefira BIBLIOTECA_ADMIN_PASSWORD para nao expor a senha no historico.")
    parser.add_argument("--timeout", type=float, default=30, help="Timeout HTTP em segundos")
    OPTIONS = parser.parse_args()
    if not OPTIONS.admin_password:
        parser.error("Defina BIBLIOTECA_ADMIN_PASSWORD com a senha do administrador do banco de testes.")
    if OPTIONS.timeout <= 0:
        parser.error("--timeout deve ser maior que zero.")
    print("Testes HTTP: use banco dedicado. Os registros smk* criados serao preservados.", flush=True)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(BibliotecaSmokeTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
