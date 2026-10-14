# Banco SQL Server

Execute os scripts, nesta ordem, no SQL Server Management Studio ou no `sqlcmd` (com interrupção em erro, opção `-b`):

1. `001-schema.sql`: cria o banco exclusivo `BibliotecaCodex_20260930`, tabelas, restrições e configuração inicial.
2. `002-procedures.sql`: cria ou atualiza as três procedures.
3. `003-demo.sql`: opcional, adiciona três livros fictícios e seis exemplares identificados por `DEMO-BD-001`, `DEMO-BD-002`, `DEMO-API-001`, `DEMO-API-002`, `DEMO-LIT-001` e `DEMO-LIT-002`.

Requer SQL Server 2016 SP1 ou posterior, com nível de compatibilidade 130 ou superior (`OPENJSON` e `CREATE OR ALTER`). SQL Server Express é suficiente para o projeto. Os scripts não removem bancos, tabelas ou dados, e não criam credenciais padrão. O script de esquema é idempotente para criação; alterações futuras em tabelas devem usar novas migrações explícitas.

As datas/horas são UTC. Limite inicial: três exemplares por leitor, prazo de 14 dias, bloqueio por atraso e self-checkout habilitado; os valores ficam em `CONFIGURACOES`.

`SP_CRIAR_EMPRESTIMO` recebe uma lista JSON de códigos de tombo (textos), por exemplo `["DEMO-BD-001","DEMO-API-001"]`. O canal `SELF_CHECKOUT` exige leitor ativo operando em nome próprio. `BALCAO` exige administrador ou bibliotecário. A API fornece a identidade do operador autenticado, nunca um operador escolhido pelo cliente.

`SP_REGISTRAR_DEVOLUCAO` recebe uma lista JSON de IDs inteiros de exemplares do empréstimo. A equipe pode devolver parte deles; o cabeçalho só é encerrado depois da última devolução. Confirmar fisicamente a devolução é responsabilidade da equipe nesta versão.

As operações são atômicas, auditadas e usam a mesma trava transacional `Biblioteca:Circulacao`. Essa serialização simples atende ao volume acadêmico; o índice único filtrado em `ITENS_EMPRESTIMO` também impede dois empréstimos abertos do mesmo exemplar. `XACT_ABORT`, `TRY/CATCH` e `ROLLBACK` evitam empréstimos ou devoluções parciais quando uma validação falha. Toda escrita de circulação deve passar pelas procedures; SQL manual por um administrador pode violar invariantes entre tabelas.

Erros de negócio das procedures: `51000` entrada inválida, `51001` não encontrado, `51002` conflito, `51003` regra de circulação, `51004` operação proibida. As procedures de circulação retornam uma linha com `IdEmprestimo`. A auditoria participa da mesma transação.

Nunca armazene senhas em texto puro. `USUARIOS.SenhaHash` recebe exclusivamente o hash gerado pela aplicação; crie o primeiro administrador pelo fluxo seguro de inicialização documentado na aplicação.
