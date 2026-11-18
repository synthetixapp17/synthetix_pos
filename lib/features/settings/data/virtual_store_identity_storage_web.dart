import 'package:web/web.dart' as web;

String? readVirtualStoreIdentity(String key) =>
    web.window.localStorage.getItem(key);

void writeVirtualStoreIdentity(String key, String value) {
  web.window.localStorage.setItem(key, value);
}
