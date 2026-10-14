import 'package:biblioteca_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mostra a tela de entrada', (tester) async {
    await tester.pumpWidget(const BibliotecaMobileApp());

    expect(find.text('Biblioteca Mobile'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Ainda não tenho cadastro'), findsOneWidget);
  });
}
