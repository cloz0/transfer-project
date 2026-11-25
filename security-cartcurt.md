# Güvenlik notu

Transfer şu anda geliştirme aşamasında bir prototiptir; güvenli dosya aktarımı olarak kullanılmaya hazır değildir.

## Mevcut sınırlar

- Dosya aktarımı ve şifreleme uygulanmamıştır.
- Cihaz keşfi, karşı cihazın kimliğini doğrulamaz.
- Eşleştirme isteği yerel ağ üzerinden kimlik doğrulaması ve şifreleme olmadan iletilir.
- Gelen isteklerin kabul veya reddi şu an karşı cihaza bildirilmez ve dosyalara erişim sağlamaz.
- Yerel ağdaki bir cihaz sahte isteklerle kullanıcıya tekrarlayan pencereler gösterebilir veya uygulamanın yanıt vermesini zorlaştırabilir.

## Güvenli kullanım

- Uygulamayı yalnızca güvendiğiniz, kontrollü bir ağda çalıştırın.
- Hassas dosyalar, kişisel veriler veya güvenilmeyen ağlar için kullanmayın.
- Tanımadığınız cihazlardan gelen istekleri onaylamayın.
- Güvenli aktarım, kimlik doğrulama ve istek sınırlama uygulanıp ayrıca incelenene kadar bu sınırların devam ettiğini varsayın.

Bu not mevcut davranışı açıklar; güvenlik sertifikası veya güvenli kullanım garantisi değildir.
