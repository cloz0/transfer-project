# UQZELA

Uqzela, aynı yerel ağdaki cihazları bulup güvenli bir eşleştirme bağlantısı kurmak için geliştirilen Flutter ve Rust tabanlı bir uygulamadır.

## Mevcut özellikler

- Aynı yerel ağdaki Uqzela cihazlarını mDNS ile keşfetme
- Android ve Linux üzerinde cihazları listeleme
- Seçilen cihaza eşleştirme isteği gönderme
- Gelen eşleştirme isteğini kabul etme veya reddetme
- Noise XX protokolüyle şifreli eşleştirme oturumu
- İki tarafta karşılaştırılabilen güvenlik kodu
- Koyu temalı, responsive Flutter arayüzü
- Yenileme, bağlantı ve eşleştirme durumları için animasyonlar

Dosya seçme ve dosya aktarımı henüz uygulanmamıştır.

## Güvenlik durumu

Eşleştirme sırasında Noise XX kullanılarak şifreli bir oturum kurulmaya çalışılır. Kullanıcılar, bağlantıyı kabul etmeden önce iki cihazda gösterilen güvenlik kodunu karşılaştırmalıdır.

Bu sürümde kalıcı cihaz kimliği, güvenilir cihaz listesi ve dosya aktarımı bulunmaz. Uygulamayı yalnızca güvendiğiniz yerel ağlarda kullanın.

Ayrıntılar için [security-cartcurt.md](./security-cartcurt.md) dosyasına bakın.

## Gereksinimler

- Flutter SDK ve Dart SDK (`^3.14.0`)
- Rust `1.100.0` toolchain
- Hedef platform için Flutter derleme araçları

## Nasıl çalışır?

1. Uygulama açılırken cihaz yerel ağda mDNS üzerinden yayınlanır.
2. Uygulama aynı ağdaki diğer Uqzela cihazlarını tarar.
3. Listeden bir cihaz seçilip eşleştirme isteği gönderilir.
4. Karşı cihaz isteği kabul eder veya reddeder.
5. Kabul öncesinde iki cihazdaki güvenlik kodu karşılaştırılır.
6. Kabul edilirse şifreli eşleştirme oturumu tamamlanır.

İletişim için sabit TCP portu `39871` kullanılır. Okul, şirket veya misafir ağları cihazlar arası bağlantıyı ya da mDNS trafiğini engelleyebilir.

## Geliştirme ortamında çalıştırma

```bash
flutter pub get
flutter run
```

Bağlı cihazları görmek için:

```bash
flutter devices
```

Linux masaüstünde çalıştırmak için:

```bash
flutter run -d linux
```

## APK oluşturma

Telefona yüklenebilir release APK oluşturmak için:

```bash
flutter build apk --release
```

APK şu klasöre oluşturulur:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Geliştirme/debug APK’sı için:

```bash
flutter build apk --debug
```

Debug APK’nın konumu:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Linux uygulaması oluşturma

```bash
flutter build linux --debug
```

Linux uygulaması şu klasöre oluşturulur:

```text
build/linux/x64/debug/bundle/transfer_app
```

Uygulamayı çalıştırmak için:

```bash
build/linux/x64/debug/bundle/transfer_app
```

Linux derlemesi için `cmake` ve `ninja` araçlarının kurulu olması gerekir.

## Teknoloji

- Flutter / Dart: arayüz
- Rust: yerel ağ keşfi ve güvenli eşleştirme protokolü
- `flutter_rust_bridge`: Flutter ile Rust arasındaki köprü
