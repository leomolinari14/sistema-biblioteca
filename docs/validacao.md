# Validação da versão 0.2

Executada em **01/10/2026**, no Windows, com .NET SDK 10.0.400 e SQL Server Express local. A API usou SQL Server real, não um substituto em memória.

## Resultados observados

- Compilação da solução em Release: **zero erros e zero avisos**, com restauração em modo travado pelo `packages.lock.json`.
- **18 testes HTTP aprovados**, nenhum ignorado, em 5,169 segundos (execução dos cenários, excluindo preparação).
- **Cinco invariantes SQL aprovadas**, verificadas depois dos cenários HTTP.
- Inspeção de dependências diretas/transitivas: `dotnet list package --vulnerable --include-transitive` não apontou pacotes vulneráveis nas fontes consultadas naquele momento. Isso não substitui auditoria de segurança.
- Banco principal preservado, com 11 tabelas, 3 livros fictícios, 6 exemplares de demonstração e sem usuário inicial antes do primeiro uso do script local.

Banco isolado da execução final: `BibliotecaTest_20261001091201`. A instância foi `.\SQLEXPRESS`. O script encerrou somente o processo da API de testes; o banco de testes permanece para inspeção no SSMS.

## Cenários HTTP

| Nº | Cenário | Resultado |
| --- | --- | --- |
| 00 | Acesso anônimo e credenciais inválidas | Aprovado |
| 01 | Leitor sem acesso a operações da equipe/administração | Aprovado |
| 02 | Autoempréstimo vinculado ao token; rejeição de identidade no corpo; comprovante privado | Aprovado |
| 03 | Códigos desconhecidos/repetidos sem criação parcial | Aprovado |
| 04 | Mistura de exemplar disponível e já emprestado com rollback integral | Aprovado |
| 05 | Limite contado sobre múltiplos empréstimos | Aprovado |
| 06 | Dois leitores tentando o mesmo exemplar simultaneamente | Aprovado |
| 07 | Devolução parcial, finalização e novo empréstimo | Aprovado |
| 08 | Desabilitar e reabilitar self-checkout | Aprovado |
| 09 | Desativação do usuário invalida token existente | Aprovado |
| 10 | Política inicial: 3 exemplares e 14 dias | Aprovado |
| 11 | Datas UTC no comprovante e ausência de hash nas respostas | Aprovado |
| 12 | Edição de livro com autor inexistente desfaz todas as mudanças | Aprovado |
| 13 | Devolução rejeita itens de outro empréstimo e itens já devolvidos | Aprovado |
| 14 | Atraso impede novo empréstimo; devolução libera o leitor | Aprovado |
| 15 | Exemplar em manutenção indisponível e estado emprestado protegido | Aprovado |
| 16 | OpenAPI contém self-checkout, devolução e autenticação Bearer | Aprovado |
| 17 | Pedidos simultâneos do mesmo leitor não ultrapassam seu limite | Aprovado |

## Invariantes SQL

1. Nenhum exemplar aparece em dois itens ainda não devolvidos.
2. A situação EMPRESTADO corresponde exatamente à existência de item pendente.
3. Cabeçalho aberto/finalizado corresponde aos itens ainda pendentes.
4. Em SELF_CHECKOUT, o operador é o próprio titular.
5. As chaves estrangeiras estão habilitadas e validadas.

## Reproduzir

Na raiz do projeto:

```powershell
dotnet build Biblioteca.slnx -c Release -p:RestoreLockedMode=true
./scripts/Test-Integration.ps1 -Python python
dotnet list src/Biblioteca.Api/Biblioteca.Api.csproj package --vulnerable --include-transitive
```

Se necessário, passe o caminho do executável Python em `-Python`. A suíte usa somente a biblioteca padrão do Python. O script SQL de invariantes é `tests/check-invariants.sql`.

Os dados gerados têm prefixo `smk`; não se executa a suíte no banco principal. O cenário de atraso altera exclusivamente as datas do empréstimo criado pelo próprio teste, em um banco `BibliotecaTest_...`. Não há alteração do relógio da máquina. A execução manual sem esse banco configurado ignora o cenário de atraso.

## Não validado nesta etapa

Interface mobile/desktop, câmera, leitor físico, acessibilidade, instalação em outro computador, HTTPS público, testes de carga, backup/restauração e auditoria de segurança aprofundada. A aprovação dos cenários acima não equivale à homologação de produção.
