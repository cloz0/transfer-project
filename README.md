# Transfer

Transfer, aynı yerel ağdaki cihazları keşfetmek ve eşleştirme isteği göndermek için geliştirilen Flutter ve Rust tabanlı bir uygulama prototipidir.

## Mevcut durum

- Aynı yerel ağdaki Transfer cihazları mDNS ile keşfedilir.
- Kullanıcı seçtiği cihaza eşleştirme isteği gönderebilir.
- Gelen istek uygulama arayüzünde kabul veya reddedilebilir; bu karar şu an karşı cihaza iletilmez.

Bu sürümde dosya aktarımı, güvenli kanal, şifreleme ve cihaz kimliğini doğrulama **uygulanmamıştır**. Eşleştirme adımları bir prototip akışıdır; ekrandaki onay, karşı cihazın kimliğini doğrulamaz. İstek ve keşif bilgileri yerel ağ üzerinden şifrelenmeden iletilir. Yerel ağdaki başka bir cihaz sahte eşleştirme istekleri göndererek uygulamada rahatsız edici pencereler açılmasına veya uygulamanın yanıt vermesinin zorlaşmasına neden olabilir. Bu nedenle uygulamayı güvenilmeyen ağlarda çalıştırmayın ve hassas bilgiler için kullanmayın.

Güvenlik kapsamı ve bu prototipin bilinen sınırları için [security-cartcurt.md](./security-cartcurt.md) dosyasına bakın.

## Gereksinimler

- Flutter SDK ve Dart SDK (Dart `^3.14.0`)
- Rust `1.100.0` toolchain
- Hedef platform için gerekli Flutter derleme araçları

Depoda bulunan `native/transfer_core/rust-toolchain.toml`, gereken Rust toolchain sürümünü belirtir. Rustup kullanıyorsanız eksik toolchain otomatik olarak kurulabilir.

## Başlatma

```bash
flutter pub get
flutter run
```

Uygulamayı kullanırken cihazların aynı yerel ağa bağlı ve Transfer'ın her iki cihazda da açık olması gerekir. Cihaz keşfi, ağın mDNS trafiğine izin vermesine bağlıdır.

## Teknoloji

- Flutter / Dart: uygulama arayüzü
- Rust: yerel ağ keşfi ve eşleştirme isteği prototipi
- `flutter_rust_bridge`: Flutter ile Rust arasındaki köprü
