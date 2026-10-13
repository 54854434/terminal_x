import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/widgets/tx_market_radar.dart';

void main(){
  testWidgets('radar shows two committed marks and switches without trading',
      (tester) async {
    var selected=-1;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      TxMarketRadar(quotes:const [
        TxRadarQuote(symbol:'SIM-A01',priceCents:1000,regime:'区间震荡'),
        TxRadarQuote(symbol:'SIM-A02',priceCents:2500,regime:'上行趋势'),
      ],selectedIndex:0,onSelect:(i)=>selected=i))));
    expect(find.text('¥10.00'),findsOneWidget);
    expect(find.text('¥25.00'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('radar-SIM-A02')));
    expect(selected,1);
    expect(tester.takeException(),isNull);
  });
  testWidgets('radar fits narrow phone screen', (tester) async {
    tester.view.physicalSize=const Size(320,640);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      SingleChildScrollView(child:TxMarketRadar(quotes:const [
        TxRadarQuote(symbol:'SIM-A01',priceCents:1000,regime:'高波动'),
        TxRadarQuote(symbol:'SIM-A02',priceCents:2500,regime:'下行趋势'),
      ],selectedIndex:1,onSelect:(_){ })))));
    expect(tester.takeException(),isNull);
  });
}
