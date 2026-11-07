// |A.1.01.02|App|Entry|Dart|lib/main.dart|A.1.01.01, C.1.01.01, D.2.01.01, D.2.01.03, D.2.01.04, P.3.01.01, S.4.01.01|v.0.0.02|Draft|—|
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MpApp()));
}