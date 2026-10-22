import 'key_value_store.dart';

Future<KeyValueStore> openPlatformStore() async => MemoryStore();
