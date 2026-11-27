import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:transfer_app/main.dart';

void main() {
  testWidgets('Gerçek keşif için başlangıç ekranı açılır', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TransferApp());

    expect(find.text('Uqzela'), findsOneWidget);
    expect(find.text('Yakındaki cihazlar'), findsOneWidget);
    expect(find.text('Henüz cihaz yok'), findsOneWidget);
    expect(find.text('Örnek telefon'), findsNothing);
    expect(find.text('Çalışma bilgisayarı'), findsNothing);
    expect(find.text('Güvenli bağlantı başlat'), findsOneWidget);
  });

  testWidgets('Cihaz seçilmeden eşleştirme başlatılamaz', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TransferApp());

    final pairingButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Güvenli bağlantı başlat'),
    );

    expect(pairingButton.onPressed, isNull);
  });
}
