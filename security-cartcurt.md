# Güvenlik notu

Uqzela'nın mevcut sürümünde güvenlik kapsamı yalnızca eşleştirme oturumu ile sınırlıdır.

## Uygulananlar

- Eşleştirme iletişiminde Noise XX protokolü kullanılır.
- Oturum trafiği ChaChaPoly ile şifrelenir.
- Ağ mesajlarında boyut sınırı ve zaman aşımı uygulanır.
- Kabul veya ret kararı şifreli oturum üzerinden gönderilir.
- Güvenlik kodu iki cihazda karşılaştırılabilir.

## Mevcut sınırlar

- Dosya aktarımı henüz uygulanmamıştır.
- Kalıcı cihaz kimliği ve güvenilir cihaz kaydı yoktur.
- Güvenlik kodu kullanıcı tarafından kontrol edilmelidir; uygulama bunu otomatik doğrulamaz.
- mDNS keşfi tek başına cihaz kimliği doğrulamaz.
- Okul, şirket veya misafir ağları cihazlar arası bağlantıyı engelleyebilir.

Bu nedenle uygulamayı yalnızca güvendiğiniz yerel ağlarda kullanın ve güvenlik kodu eşleşmeyen bir isteği kabul etmeyin.
