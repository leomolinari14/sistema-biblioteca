# Como rodar a Biblioteca no desktop e no Android

Este repositório contém o sistema web/API na raiz e o aplicativo Flutter em `mobile/`. Não é necessário Docker.

## 1. Requisitos do sistema desktop

No computador que executará o servidor, instale:

1. [.NET 10 SDK para Windows x64](https://dotnet.microsoft.com/download/dotnet/10.0) — escolha o SDK, não apenas o Runtime.
2. [SQL Server Express](https://www.microsoft.com/sql-server/sql-server-downloads), usando a instância padrão `SQLEXPRESS`.
3. [`sqlcmd`](https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install).

Execute `Verificar-Requisitos.cmd` antes da apresentação. Se o SQL Server estiver instalado, mas parado, abra o PowerShell como administrador e execute:

```powershell
Start-Service 'MSSQL$SQLEXPRESS'
```

## 2. Rodar a versão desktop

1. Clone ou baixe o repositório e extraia todos os arquivos.
2. Execute `Iniciar-Biblioteca.cmd`.
3. Na primeira execução, escolha uma senha de 10 a 128 caracteres para o usuário `admin`.
4. Aguarde aparecer `Now listening on: http://127.0.0.1:5180`.
5. Execute `Abrir-no-Navegador.cmd` ou abra <http://127.0.0.1:5180>.

Mantenha a janela do servidor aberta. Para encerrar, pressione `Ctrl+C` nela. O banco, os usuários e os empréstimos permanecem armazenados no SQL Server.

## 3. Rodar o mobile no emulador

Instale Android Studio, Flutter e os plugins Flutter/Dart. Depois:

1. Inicie o servidor com `Iniciar-Biblioteca.cmd`.
2. No Android Studio, abra a pasta `mobile/`.
3. Abra o Device Manager e inicie um emulador Android.
4. Selecione o emulador no topo da IDE — não selecione Windows (desktop).
5. Abra `mobile/lib/main.dart` e clique em **Run**.
6. Na tela de login, mantenha o endereço `http://10.0.2.2:5180`.

O endereço `10.0.2.2` é a forma usada pelo emulador Android para acessar o computador anfitrião.

## 4. Rodar em um celular físico

1. Conecte o computador e o celular à mesma rede Wi-Fi.
2. Execute `Iniciar-Biblioteca-Rede-Local.cmd`.
3. Quando o Firewall do Windows perguntar, permita acesso pela rede privada.
4. Instale `distribuicao/Biblioteca-Mobile-arm64.apk` no celular.
5. No aplicativo, informe um dos endereços mostrados pelo servidor, como `http://192.168.0.10:5180`.

O APK é destinado a celulares Android ARM64 atuais. O Android pode solicitar autorização para instalar aplicativos dessa origem. Use o modo de rede local somente em redes confiáveis.

## 5. Usuários e senhas

### Administrador web

- Usuário: `admin`
- Senha: definida na primeira inicialização do servidor

### Aluno no aplicativo

Não existe aluno padrão. Toque em **Ainda não tenho cadastro** e crie uma conta. Exemplo:

```text
Nome: Aluno Teste
E-mail: aluno@teste.com
Usuário: aluno
Senha: AlunoTeste123!
```

## 6. Simular empréstimo e devolução

No catálogo mobile, toque em um livro para visualizar e copiar os códigos dos exemplares. A base de demonstração contém:

```text
DEMO-BD-001
DEMO-BD-002
DEMO-API-001
DEMO-API-002
DEMO-LIT-001
DEMO-LIT-002
```

Para emprestar, entre como aluno, abra **Checkout → Emprestar**, adicione um código disponível e confirme. Para devolver, abra **Checkout → Devolver**, informe um código emprestado para o aluno atual e confirme.

## 7. Gerar um novo APK

No terminal, dentro da pasta `mobile/`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

O APK será criado em `mobile/build/app/outputs/flutter-apk/app-release.apk`.

## 8. Solução rápida de problemas

- **SQL Server não encontrado:** confirme que `SQL Server (SQLEXPRESS)` está em execução.
- **Invalid Hostname no emulador:** encerre o servidor com `Ctrl+C`, atualize o projeto e execute novamente `Iniciar-Biblioteca.cmd`.
- **Celular não acessa o servidor:** confirme o mesmo Wi-Fi, o IP informado e a permissão de rede privada no Firewall.
- **Android Studio tenta executar no Windows:** inicie e selecione um emulador Android antes de clicar em Run.
- **CMD fecha rapidamente:** abra o PowerShell nessa pasta e rode `./scripts/Start-Local.ps1` para manter a mensagem de erro visível.

Para detalhes do backend e do banco, consulte [README.md](README.md) e [COMO-RODAR-EM-OUTRO-PC.md](COMO-RODAR-EM-OUTRO-PC.md).
