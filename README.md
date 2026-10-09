# GSBDPI

KYK / GSB yurt internetinde Discord ve erişim engeli bulunan siteleri VPN kullanmadan açabilmeniz için hazırlanmış GoodbyeDPI paketi.

Yurt ağlarındaki kısıtlamaları aşacak şekilde ayarlanmıştır; yurt giriş sayfası (`wifi.gsb.gov.tr`) ve e-Devlet gibi siteler etkilenmez.

---

## Kurulum ve Kullanım

1. Yeşil **Code** butonuna tıklayıp **Download ZIP** seçeneğiyle indirin ve dosyaları bir klasöre çıkartın.
2. Klasör içindeki `kyk_test.exe` dosyasını çalıştırın (yönetici izni isteyecektir).
3. Program yurdunuzun bağlantısını test edip en stabil çalışan ayarı bulur ve size özel `KYK_BASLAT.cmd` dosyasını oluşturur.
4. Çıkan ekranda **1** tuşuna basarak hemen başlatabilirsiniz. Sonraki kullanımlarda doğrudan `KYK_BASLAT.cmd` dosyasını açmanız yeterlidir.

> **İpucu:** Her açılışta elle çalıştırmak istemiyorsanız, test ekranında **2** seçeneğini seçerek arka planda Windows hizmeti olarak kurabilirsiniz. Kaldırmak için klasördeki `service_remove_gsb_kyk.cmd` dosyasını yönetici olarak çalıştırmanız yeterlidir.

---

## Önemli Notlar

- **Kapatmak için:** Açık olan komut penceresini kapatmanız yeterlidir.
- **Discord Ses Kanalları (RTC):** Discord mesajları, güncellemeleri ve sunucuları sorunsuz açılır. Ancak bazı yurtlarda ses için kullanılan UDP portları tamamen engellendiği için ses kanalına bağlanamayabilirsiniz. Bu durumda Discord'u tarayıcı üzerinden (`discord.com/app`) kullanmayı deneyebilirsiniz (tarayıcılar ses aktarımını web üzerinden iletebilir).
- **Yurt İnternetine Giriş:** `wifi.gsb.gov.tr`, `kyk.gov.tr` ve kamu siteleri listeye dahil edilmemiştir; kota veya giriş ekranında kopma yaşamazsınız.

---

## Lisans

Bu proje [ValdikSS/GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) tabanlıdır ve Apache License 2.0 ile lisanslanmıştır.
