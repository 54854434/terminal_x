import 'package:flutter/material.dart';
import 'tx_terminal_theme.dart';

/// Small read-only snapshot picker: prices are durable reference marks.
/// Selecting a row updates the local active symbol, never places an order.
class TxRadarQuote {
  const TxRadarQuote({required this.symbol,required this.priceCents,
    required this.regime});
  final String symbol;
  final int priceCents;
  final String regime;
}

class TxMarketRadar extends StatelessWidget {
  const TxMarketRadar({super.key,required this.quotes,
    required this.selectedIndex,required this.onSelect});
  final List<TxRadarQuote> quotes;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:9),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Padding(padding:EdgeInsets.only(bottom:5),child:Text(
        '模拟市场雷达 · 点击切换',style:TextStyle(fontSize:12,
        color:TxTerminalColors.secondaryText))),
      for(var i=0;i<quotes.length;i++) InkWell(
        key:ValueKey('radar-${quotes[i].symbol}'),
        borderRadius:BorderRadius.circular(9),
        onTap:()=>onSelect(i),
        child:Container(width:double.infinity,
          margin:const EdgeInsets.symmetric(vertical:3),
          padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
          decoration:BoxDecoration(borderRadius:BorderRadius.circular(9),
            color:i==selectedIndex?TxTerminalColors.raised:Colors.transparent,
            border:Border.all(color:i==selectedIndex?
              TxTerminalColors.primary:TxTerminalColors.border)),
          child:Row(children:[
            Icon(i==selectedIndex?Icons.radio_button_checked:
              Icons.radio_button_unchecked,size:16,
              color:i==selectedIndex?TxTerminalColors.primary:
                TxTerminalColors.secondaryText),
            const SizedBox(width:9),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[Text(quotes[i].symbol,style:const TextStyle(
                fontWeight:FontWeight.w700,fontSize:13)),
                Text(quotes[i].regime,style:const TextStyle(
                  fontSize:10,color:TxTerminalColors.secondaryText))])),
            Text('¥${(quotes[i].priceCents/100).toStringAsFixed(2)}',
              style:const TextStyle(fontSize:15,fontWeight:FontWeight.w700)),
          ]))),
    ]),
  ));
}
