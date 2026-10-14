# Autoatendimento (self-checkout)

O self-checkout permite que o aluno registre o empréstimo e a devolução dos exemplares usando sua própria conta. Neste sistema de biblioteca, significa **autoatendimento**, sem carrinho de compras, cobrança ou pagamento.

## Escopo da primeira versão

O leitor autentica-se, informa os códigos de tombo dos exemplares e confirma o empréstimo. A API registra todos os itens na mesma operação e retorna um comprovante com o identificador do empréstimo, os exemplares e o prazo de devolução. O leitor consulta seus empréstimos e seus comprovantes pela API.

O código identifica o **exemplar físico**, não apenas o título ou ISBN. Dois exemplares do mesmo livro têm códigos de tombo diferentes e podem ser emprestados separadamente. Uma etiqueta com código de barras ou QR Code pode representar esse mesmo código. Um leitor USB que funciona como teclado e a leitura por câmera são possibilidades para a futura interface mobile/desktop; a API já recebe o código textual necessário a essas integrações. Esta entrega não pressupõe hardware RFID, catraca ou conferência física automática.

O aluno também pode informar os códigos de tombo no modo **Devolver**. A API aceita somente exemplares que estejam emprestados para a própria conta. A equipe continua podendo registrar devoluções no balcão. A devolução pode abranger apenas parte dos itens; o empréstimo só fica finalizado depois que todos forem devolvidos.

## Regras adotadas

| Regra | Comportamento inicial |
| --- | --- |
| Identidade | O usuário do empréstimo vem da autenticação; o leitor não escolhe outra pessoa. |
| Limite | Até 3 exemplares ainda não devolvidos por leitor, somando todos os empréstimos. |
| Prazo | 14 dias, calculados no servidor. |
| Atrasos | Um leitor com item em atraso fica impedido de fazer novo empréstimo quando o bloqueio está habilitado. |
| Disponibilidade | Apenas exemplares disponíveis podem ser emprestados. |
| Códigos repetidos | Um mesmo exemplar não pode aparecer duas vezes na solicitação. |
| Confirmação | Todos os itens são registrados, ou nenhum; não existe confirmação parcial silenciosa. |
| Concorrência | Se dois leitores tentarem o mesmo exemplar, somente um empréstimo pode ser confirmado. |
| Conta desativada | O acesso deixa de ser aceito, inclusive com token obtido antes da desativação. |
| Controle da biblioteca | O administrador pode habilitar/desabilitar o self-checkout e alterar limite, prazo e bloqueio de atrasos. |

Os valores de 3 exemplares e 14 dias são **parâmetros provisórios do projeto**, sujeitos à validação com o professor. Alterar a configuração não deve recalcular o vencimento de empréstimos já registrados. Multas, reservas, renovações e pagamentos não fazem parte deste fluxo inicial.

## Fluxo de uso e arquitetura

```mermaid
sequenceDiagram
    actor Leitor
    participant Cliente as Cliente mobile ou desktop
    participant API as API ASP.NET Core
    participant DB as SQL Server
    Leitor->>Cliente: Entrar com usuário e senha
    Cliente->>API: POST /api/v1/auth/login
    API-->>Cliente: Token de acesso
    Leitor->>Cliente: Informar ou ler códigos de tombo
    Cliente->>API: GET /api/v1/exemplares/codigo/{codigo}
    API-->>Cliente: Dados do exemplar
    Leitor->>Cliente: Confirmar todos os exemplares
    Cliente->>API: POST /api/v1/self-checkout/emprestimos
    API->>API: Identificar leitor e validar acesso
    API->>DB: Iniciar transação e proteger validações concorrentes
    API->>DB: Validar política, atrasos, limite e disponibilidade
    alt Todos os itens são válidos
        API->>DB: Gravar empréstimo, itens e auditoria
        API->>DB: Confirmar transação
        API-->>Cliente: 201 + comprovante
        Cliente-->>Leitor: Exibir exemplares e vencimento
    else Alguma regra impede a operação
        API->>DB: Reverter transação
        API-->>Cliente: Erro com motivo; nenhum item confirmado
        Cliente-->>Leitor: Exibir correção necessária
    end
```

A consulta inicial de disponibilidade serve para orientar o leitor. A validação decisiva ocorre na transação que confirma o empréstimo, porque outro leitor pode retirar o exemplar entre a consulta e a confirmação. Os clientes se comunicam com a API; somente o servidor acessa o banco de dados.

## Contrato principal da API

As chamadas protegidas enviam o cabeçalho `Authorization: Bearer <token>`. Em produção, a comunicação deve usar HTTPS.

```http
POST /api/v1/self-checkout/emprestimos
Content-Type: application/json
Authorization: Bearer <token-do-leitor>

{
  "codigosExemplares": ["BIB-00001", "BIB-00002"]
}
```

O corpo não inclui `idUsuario`, data de vencimento, limite ou estado de disponibilidade. Esses valores são determinados pelo servidor. Campos JSON desconhecidos são rejeitados; um `idUsuario` acrescentado manualmente ao pedido causa erro `400`, sem registrar empréstimo.

| Operação | Acesso e finalidade |
| --- | --- |
| `POST /api/v1/auth/login` | Autenticar e obter token. |
| `GET /api/v1/exemplares/codigo/{codigo}` | Usuário autenticado consulta o exemplar pelo código. |
| `POST /api/v1/self-checkout/emprestimos` | Leitor registra empréstimo para si mesmo. |
| `POST /api/v1/self-checkout/devolucoes` | Leitor devolve, por código de tombo, exemplares da própria conta. |
| `GET /api/v1/me/emprestimos?page=1&pageSize=20` | Usuário consulta seus próprios empréstimos, com paginação. |
| `GET /api/v1/emprestimos/{id}` | O titular ou um funcionário autorizado consulta o comprovante. |
| `POST /api/v1/emprestimos` | Funcionário registra um empréstimo no atendimento. |
| `POST /api/v1/emprestimos/{id}/devolucoes` | Funcionário registra devolução de uma lista de `idsExemplares`. |
| `GET /api/v1/configuracoes` | Usuário autenticado consulta a política vigente. |
| `PUT /api/v1/configuracoes` | Administrador modifica a política. |

O sucesso da confirmação retorna `201`. O comprovante contém `idEmprestimo`, `idUsuario`, `canal`, `situacao`, datas e a coleção `itens`, que identifica os exemplares. A situação é `ABERTO` enquanto houver itens pendentes e `FINALIZADO` após a última devolução.

Falta de autenticação ou conta desativada retorna `401`; ação sem permissão retorna `403`; comprovante de outra pessoa ou código de exemplar inexistente retorna `404`; exemplar já emprestado retorna `409`; limite atingido, bloqueio por atraso ou self-checkout desabilitado retorna `422`. Dados inválidos são rejeitados com mensagem no formato Problem Details, incluindo `detail` quando aplicável.

Uma falha de rede após a confirmação pode impedir que o cliente veja o comprovante, embora o empréstimo já tenha sido gravado. Antes de repetir o pedido, a interface deve consultar os empréstimos do leitor. A versão inicial não oferece chave de idempotência para repetir automaticamente a confirmação.

## Critérios de verificação

O arquivo `tests/smoke.py` executa testes HTTP reais em uma API já iniciada e conectada a um **banco exclusivo de testes**. Ele cria leitores e acervo com prefixo `smk`, sem apagar registros. Usa somente a biblioteca padrão do Python, não precisa de pacotes extras e lê a senha administrativa da variável `BIBLIOTECA_ADMIN_PASSWORD`.

```powershell
# Com a API de testes em execução e BIBLIOTECA_ADMIN_PASSWORD já definida:
python tests/smoke.py --base-url http://127.0.0.1:5180
```

O script admite `BIBLIOTECA_ADMIN_USERNAME` ou `--admin-username` para outro nome de administrador. A opção `--admin-password` existe, mas a variável de ambiente é preferível para evitar senha no histórico do terminal. Tokens e senhas não devem ser copiados para documentação, prints ou logs.

São verificados: acesso anônimo, senha inválida, permissões do leitor, titularidade do empréstimo, privacidade do comprovante, código desconhecido, código duplicado, rejeição sem gravação parcial, limite entre múltiplos empréstimos, corrida entre dois leitores, devolução parcial e final, novo empréstimo após a devolução, desativação do serviço e invalidação do acesso de usuário desativado. A configuração alterada pelo teste é restaurada ao final desse cenário. Os demais dados são preservados para inspeção.

O cenário de atraso usa uma massa controlada no banco de testes: `scripts/Test-Integration.ps1` passa o nome de um banco `BibliotecaTest_...` ao teste, que altera as datas apenas do empréstimo criado pelo próprio cenário e confere o bloqueio HTTP. Quando executado manualmente sem essa configuração, o cenário é marcado como ignorado. A validação de leitura por câmera, etiquetas físicas e usabilidade fica para a implementação da interface.
