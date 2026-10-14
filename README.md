# Biblioteca - API e self-checkout

> **Pacote unificado:** esta cópia também contém a interface em `src/Biblioteca.Api/wwwroot`. Para executar interface, API e banco juntos em outro computador, comece por [COMO-RODAR-EM-OUTRO-PC.md](COMO-RODAR-EM-OUTRO-PC.md) e use `Iniciar-Biblioteca.cmd`.

Aplicação local completa em **C# / ASP.NET Core 10 + SQL Server**, com interface web e API no mesmo endereço. Ela permite catálogo, cadastro de alunos, gestão de usuários, empréstimos de balcão, autoempréstimo, devoluções parciais e auditoria.

O self-checkout permite que o **aluno empreste e devolva exemplares usando a própria conta**. O painel do aluno contém self-checkout, seus empréstimos e catálogo; funções de administração e auditoria não aparecem e também são bloqueadas pela API.

## Executar no Windows

Pré-requisitos: .NET SDK 10, SQL Server (Express atende), `sqlcmd` e PowerShell. Abra o terminal nesta pasta. No ambiente onde o projeto foi desenvolvido, todos já estão disponíveis e a instância é `.\SQLEXPRESS`.

```powershell
./scripts/Start-Local.ps1
```

O script cria o banco exclusivo `BibliotecaCodex_20260930`, aplica tabelas/procedures e inclui 3 títulos fictícios e 6 exemplares de demonstração. Na primeira execução, solicita uma senha de 10 a 128 caracteres para o usuário **admin**. A senha é armazenada somente como hash. Não há senha padrão. Nas execuções seguintes, a conta existente é preservada.

A API fica em `http://127.0.0.1:5180`. O terminal permanece ocupado enquanto ela roda; `Ctrl+C` encerra o servidor.

Para conectar o aplicativo Flutter em um celular na mesma rede Wi-Fi, execute `Iniciar-Biblioteca-Rede-Local.cmd`. O script mostra o endereço que deve ser informado no aplicativo e libera o host apenas enquanto essa execução estiver aberta.

| Endereço | Uso |
| --- | --- |
| `/health` | Confere acesso ao banco. |
| `/openapi/v1.json` | Especificação OpenAPI, importável no Postman/Insomnia. |
| `/api/v1/auth/login` | Login com `username` e `senha`. |
| `/api/v1/auth/cadastro-aluno` | Cadastro público, sempre com perfil de aluno. |

Para outra instância local: `./scripts/Start-Local.ps1 -Server 'SERVIDOR\INSTANCIA'`. Os scripts usam autenticação integrada do Windows. A conta executora precisa ter permissão para criar o banco na primeira execução.

Também é possível abrir `Biblioteca.slnx` no Visual Studio, executar `scripts/Initialize-Database.ps1 -Demo` e configurar `Bootstrap:AdminPassword` em user-secrets antes de iniciar o projeto. O perfil de desenvolvimento usa a mesma porta 5180.

## Primeiro autoempréstimo

1. Na tela inicial, use **Cadastrar aluno** e crie uma conta.
2. Entre com a conta criada. O sistema atribui o perfil `LEITOR` automaticamente.
3. Use o painel de self-checkout para adicionar os códigos de tombo.
4. Consulte `GET /api/v1/exemplares/codigo/DEMO-BD-001`.
5. Confirme em `POST /api/v1/self-checkout/emprestimos`:

```json
{ "codigosExemplares": ["DEMO-BD-001"] }
```

O sucesso retorna HTTP 201 com `idEmprestimo`, prazo e `itens`. Consulte `GET /api/v1/me/emprestimos` para o histórico próprio. Um funcionário registra a devolução em `POST /api/v1/emprestimos/{id}/devolucoes`, enviando `idsExemplares`.

Veja requisições editáveis em `docs/requisicoes.http` e as regras completas em [self-checkout.md](docs/self-checkout.md).

## O que está implementado

- JWT de 60 minutos, hash de senha e perfis ADMINISTRADOR, BIBLIOTECARIO e LEITOR.
- Autocadastro de alunos com perfil fixo e cadastro administrativo de usuários.
- Painel do aluno sem funções administrativas ou auditoria.
- Exclusão de alunos sem histórico de empréstimos, disponível somente para administradores.
- Consulta de usuários; ativação/desativação por administrador.
- Cadastro, consulta e edição de livros, editoras, autores e categorias; relação N:N de autores.
- Exemplares com código único, disponibilidade, manutenção e inativação.
- Empréstimo com vários exemplares, no balcão ou pelo próprio leitor.
- Auto devolução por código de tombo, restrita aos exemplares emprestados para o próprio aluno.
- Comprovante restrito ao titular e à equipe; histórico paginado.
- Devolução parcial e encerramento após a última devolução.
- Prazo, limite, bloqueio por atraso e habilitação do self-checkout configuráveis.
- Auditoria por procedure, acessível apenas a administradores.
- Proteção contra empréstimo simultâneo do mesmo exemplar e contra ultrapassar o limite em requisições concorrentes.

Os padrões iniciais são **3 exemplares em aberto por leitor e 14 dias**. São configurações provisórias para validar com o professor. Reservas, multas e renovação ficam fora desta versão.

## Estrutura e banco

```text
Biblioteca.slnx
src/Biblioteca.Api/
  Features/          catálogo, circulação e self-checkout
  Security/          login, perfis, usuários e administrador inicial
  Data/              conexão SQL e auditoria
  Infrastructure/    validação, erros, UTC e OpenAPI
database/
  001-schema.sql     11 tabelas, chaves, restrições e índices
  002-procedures.sql empréstimo, devolução e log
  003-demo.sql       catálogo fictício, sem usuários ou senhas
scripts/             inicialização e testes
tests/               cenários HTTP e invariantes SQL
docs/                arquitetura, regras e requisições
```

O projeto usa Dapper para SQL parametrizado explícito e procedures para circulação. Não usa banco em memória. O esquema conserva os conceitos das aulas: PK/FK, N:N, transações, concorrência, `NEWID()` no log e valores padrão no banco.

As procedures executam `BEGIN TRANSACTION`, validam as condições atuais, registram cabeçalho/itens/disponibilidade/log e fazem `COMMIT`; qualquer erro desfaz tudo. Um índice único filtrado impede duas linhas abertas para o mesmo exemplar. A trava global de circulação serializa as operações curtas deste MVP; para alto volume será necessário rever a granularidade.

## Testar

```powershell
dotnet build Biblioteca.slnx
./scripts/Test-Integration.ps1 -Python python
```

O script cria um banco novo com prefixo `BibliotecaTest_`, gera credenciais efêmeras, inicia uma API de teste na porta 5181, executa os cenários e encerra somente esse processo. O banco de teste é preservado para consulta no SSMS, e seu nome aparece ao final. O banco principal não recebe os registros `smk*`.

Requer Python 3 e `sqlcmd`; Python não precisa de pacotes adicionais. Caso Python não esteja no PATH, passe o caminho completo em `-Python`. Os testes verificam autenticação, perfis, atomicidade, concorrência, limites, atrasos, devolução, manutenção, timestamps UTC, privacidade e OpenAPI. Consulte [validacao.md](docs/validacao.md) para os resultados registrados.

## Configuração

| Chave | Uso |
| --- | --- |
| `ConnectionStrings:Biblioteca` | Conexão SQL Server. O padrão local usa autenticação Windows. |
| `Bootstrap:AdminPassword` | Cria o primeiro administrador; só atua se nenhum administrador existir. |
| `Jwt:Key` | Chave de assinatura com pelo menos 32 caracteres. Em Development, se omitida, é gerada em memória e muda a cada reinício. |
| `Cors:Origins` | Lista de origens da futura interface; por padrão nenhuma origem externa é liberada. |
| `AllowedHosts` | Por padrão, somente localhost/127.0.0.1; o iniciador de rede local libera temporariamente os hosts. |

Variáveis de ambiente usam dois sublinhados: `ConnectionStrings__Biblioteca`, `Bootstrap__AdminPassword` e `Jwt__Key`. Em servidor publicado, configure HTTPS, chave persistente, host/origens da aplicação, credencial SQL com privilégios restritos e certificado confiável. A configuração incluída é para execução local.

Datas/horários de circulação são UTC e a API os devolve com `Z`. A aquisição é uma data de catálogo; no modelo inicial ela é transportada como data/hora UTC à meia-noite. A futura interface deve exibi-la como data, sem converter para o dia anterior.

## Documentação

- [Arquitetura atual v0.2](docs/arquitetura.md)
- [PDF técnico v0.2 com diagramas](docs/arquitetura-v0.2.pdf)
- [Regras e fluxo do self-checkout](docs/self-checkout.md)
- [Requisições de exemplo](docs/requisicoes.http)
- [Validação executada](docs/validacao.md)
- [Detalhes dos scripts SQL](database/README.md)

O PDF v0.1 criado anteriormente registra o planejamento inicial. Os documentos desta pasta e o PDF v0.2 descrevem a implementação atual, incluindo o self-checkout solicitado depois. Para regenerar o PDF, execute `python scripts/Build-Documentation.py` em um ambiente com `reportlab`; essa biblioteca não é necessária para executar a API ou os testes.
