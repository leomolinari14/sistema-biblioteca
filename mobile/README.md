# Biblioteca Mobile

Aplicativo Android feito em Flutter e Dart para os alunos da Biblioteca.

## Funcionalidades

- login e cadastro de aluno;
- catálogo de livros;
- consulta dos próprios empréstimos;
- self-checkout para emprestar exemplares;
- self-checkout para devolver exemplares;
- nenhuma função administrativa ou de auditoria.

## Rodar no emulador Android

1. Inicie a API da Biblioteca no computador.
2. Abra esta pasta no Android Studio ou execute `flutter run`.
3. Na tela de login, mantenha `http://10.0.2.2:5180` como servidor.

## Rodar em um celular físico

1. Conecte o celular e o computador à mesma rede Wi-Fi.
2. Inicie o sistema do computador com `Iniciar-Biblioteca-Rede-Local.cmd`.
3. Permita o acesso no Firewall do Windows quando ele perguntar.
4. Use no aplicativo o endereço mostrado pelo script, por exemplo `http://192.168.0.10:5180`.

## Gerar o APK

```powershell
flutter build apk --release
```

O arquivo será criado em `build/app/outputs/flutter-apk/app-release.apk`.
