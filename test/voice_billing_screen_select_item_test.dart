// Confirming widget test for BUG-5b — SECOND, corrected trigger.
//
// The prior widget test (`voice_billing_screen_test.dart`) confirmed the
// Architect's "double-tap on हाथ से बनाएं" hypothesis did NOT reproduce the
// crash. Production instrumentation (`[BUG-5b]` debugPrint) then caught a
// REAL recurrence and proved that hypothesis wrong directly: only one clean,
// non-overlapping `_addManualItem()`/`_showItemPicker()` pair, 416ms apart.
// The user's own description of the action ("after clicking on item")
// pinpointed the real trigger: tapping an item INSIDE the already-open
// picker sheet to select it, not opening the sheet itself.
//
// That handler (`_showItemPicker`'s `ListTile.onTap`,
// `voice_billing_screen.dart`) does exactly the same class of thing the
// first hypothesis was about, but on the closing side instead of the
// opening side:
//   onTap: () { _selectItem(index, s.itemName); Navigator.pop(ctx); }
// `_selectItem` calls `setState()` on the underlying screen (schedules a
// pending rebuild) and `Navigator.pop(ctx)` tears down the modal route —
// both fired synchronously, in the same handler, with an autofocus keyboard
// also needing to dismiss as part of the pop. This test forces exactly that
// sequence and is written FIRST, run against the code before any fix for
// this specific handler, per this project's root-cause discipline.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartdukan/models/models.dart';
import 'package:smartdukan/screens/voice_billing_screen.dart';

void main() {
  testWidgets(
    'BUG-5b: selecting an item from the manual item-picker must not throw',
    (tester) async {
      final testStock = [
        StockItem(
          id: 'test-1',
          currentStock: 50,
          sellingPrice: 10,
          lowStockLimit: 5,
          aliases: const [],
          itemName: 'QA Test Item',
          category: 'test',
          unit: 'मिली',
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        home: VoiceBillingScreen(
          onRegisterReload: (_) {},
          initialStockForTest: testStock,
        ),
      ));
      await tester.pumpAndSettle();

      // Enter manual mode — opens the item-picker sheet for the new blank
      // row (deferred one frame by the earlier BUG-5b fix; pumpAndSettle
      // carries us past that).
      await tester.tap(find.text('हाथ से बनाएं'));
      await tester.pumpAndSettle();

      // The picker sheet should now show our seeded stock item.
      final itemFinder = find.text('QA Test Item');
      expect(itemFinder, findsOneWidget);

      // The real repro: tap it to select it — this fires _selectItem()
      // (setState on the parent) and Navigator.pop(ctx) (modal teardown)
      // synchronously, in the same handler, with the picker's autofocus
      // keyboard also dismissing as part of the pop.
      await tester.tap(itemFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
