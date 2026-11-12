// |A.1.01.02|App|Entry|Dart|lib/main.dart|A.1.01.01|v.0.0.03|Draft|—|
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MpApp()));
}