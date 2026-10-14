# Biblioteca completa — execução em outro computador

Este pacote contém a interface e o backend na mesma pasta. A própria API entrega a interface; não é necessário iniciar um segundo servidor, Python ou Docker.

## O que instalar no outro computador

Instale estes três componentes:

1. [.NET 10 SDK para Windows x64](https://dotnet.microsoft.com/download/dotnet/10.0) — escolha **SDK**, não apenas Runtime.
2. [SQL Server 2025 Express](https://www.microsoft.com/sql-server/sql-server-downloads) — a instalação padrão deve criar a instância `SQLEXPRESS`.
3. [`sqlcmd` para Windows](https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install) — necessário para criar as tabelas e procedures automaticamente.

As instalações do SQL Server e do `sqlcmd` normalmente exigem permissão de administrador. Faça isso antes do dia da apresentação.

## Primeira execução

1. Extraia todo o ZIP para uma pasta local. Não execute de dentro do ZIP.
2. Execute `Verificar-Requisitos.cmd`.
3. Quando todos os itens aparecerem como **OK**, execute `Iniciar-Biblioteca.cmd`.
4. Na primeira execução, escolha uma senha de 10 a 128 caracteres para o usuário `admin`.
5. Aguarde aparecer `Now listening on: http://127.0.0.1:5180`.
6. Execute `Abrir-no-Navegador.cmd` ou acesse <http://127.0.0.1:5180>.

Mantenha a janela preta aberta enquanto estiver usando o sistema. Para encerrar, volte à janela e pressione `Ctrl+C`.

## Próximas execuções

Basta executar `Iniciar-Biblioteca.cmd` e depois `Abrir-no-Navegador.cmd`. O banco, os usuários e os empréstimos permanecem gravados no SQL Server desse computador.

## Usar o aplicativo no celular

1. Conecte o celular e o computador à mesma rede Wi-Fi.
2. Execute `Iniciar-Biblioteca-Rede-Local.cmd` no computador.
3. Se o Firewall do Windows perguntar, permita o acesso pela rede privada.
4. No aplicativo, informe um dos endereços exibidos na janela, como `http://192.168.0.10:5180`.

Use o iniciador normal quando quiser acesso somente no próprio computador. O modo de rede local deve ser usado apenas em uma rede confiável, durante o uso do aplicativo.

## Se o SQL Server tiver outro nome

Abra o PowerShell nesta pasta e execute:

```powershell
./scripts/Start-Local.ps1 -Server '.\NOME_DA_INSTANCIA'
```

## Importante para a apresentação

Faça uma execução completa no computador da faculdade com antecedência. Copiar apenas a pasta não instala o .NET nem o SQL Server; esses componentes precisam estar instalados na máquina que executará o sistema.
