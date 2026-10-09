# 🎓 GSBDPI — GSB / KYK Yurt İnterneti İçin GoodbyeDPI & Teşhis Aracı

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011%20(x64%20%7C%20x86)-blue?style=for-the-badge&logo=windows" alt="Platform">
  <img src="https://img.shields.io/badge/KYK%20Wi--Fi-Uyumlu-success?style=for-the-badge" alt="KYK Wi-Fi Uyumlu">
  <img src="https://img.shields.io/badge/DNS--over--HTTPS-Aktif%20(1.1.1.1%20%2F%208.8.8.8)-purple?style=for-the-badge" alt="DoH Aktif">
  <img src="https://img.shields.io/badge/Lisans-Apache%202.0-orange?style=for-the-badge" alt="Lisans">
</p>

Bu proje, Türkiye'deki üniversite ve Kredi Yurtlar Kurumu (KYK / GSB) yurtlarında kullanılan kurumsal internet altyapısında (**GSB Wi-Fi**) ve Türk Telekom hatlarında **GoodbyeDPI** motoru ile Discord ve engelli siteleri sorunsuz şekilde çalıştırmanız için geliştirilmiş özel ve optimize edilmiş bir çözümdür.

---

## ✨ Öne Çıkan Özellikler

- 🚀 **Otomatik Teşhis ve Test Aracı (`kyk_test.exe`):** Yurdunuzdaki güvenlik duvarı tipini (DNS gaspı, Stateful TCP incelemesi, TTL mesafesi) saniyeler içinde analiz eder ve en hızlı çalışan modu otomatik tespit edip başlatıcı oluşturur.
- 🔒 **Dahili Şeffaf DNS-over-HTTPS (DoH):** Yurdun UDP/53 DNS ele geçirmesini (hijack) aşmak için tüm sistem DNS sorgularını arka planda şifreli TLS (RFC 8484) üzerinden Cloudflare (`1.1.1.1`) ve Google (`8.8.8.8`) sunucularına iletir. **`hosts` dosyasını değiştirmeye gerek kalmaz!**
- 🛡️ **Kurumsal & Eğitim Siteleri Beyaz Listesi:** `wifi.gsb.gov.tr`, `kyk.gov.tr`, `turkiye.gov.tr`, `edevlet.gov.tr`, `meb.gov.tr`, `osym.gov.tr`, `yok.gov.tr` gibi kurumsal alan adları filtreden muaf tutulur. Yurt giriş sayfası ve e-Devlet asla kopmaz.
- ⚡ **Mod -5 & TTL 5 Zehirleme Desteği:** Türk Telekom / KYK Stateful DPI engellerini sahte paket (fake packet) ve otomatik TTL manipülasyonu ile kusursuzca aşar.
- 🔇 **QUIC Engellemesi (`-q`):** Discord ses ve tarayıcı akışlarını kararsız UDP yerine güvenli TCP moduna düşürerek bağlantı kopmalarını önler.
- ⚙️ **Windows Hizmeti (Service) Desteği:** İster tek tıkla konsoldan çalıştırın, isterseniz Windows arka plan hizmeti olarak kurup bilgisayar her açıldığında otomatik başlamasını sağlayın.

---

## ⚡ Hızlı Başlangıç (1 Tıkla Kurulum)

### Adım 1: İndirin
Sağ üstteki **`Code` -> `Download ZIP`** butonuna tıklayarak projeyi indirin ve bir klasöre çıkartın.

### Adım 2: Test Aracını Çalıştırın
Klasör içerisindeki **`kyk_test.exe`** dosyasına çift tıklayın (araç yönetici iznini otomatik isteyecektir).

Araç sırasıyla:
1. Yurdunuzun DNS yapısını ve DoH erişimini analiz eder.
2. Arka planda 6 farklı DPI atlatma mekanizmasını canlı olarak test eder.
3. Yurdunuz için **en hızlı ve en stabil modu** belirler.
4. Size özel **`KYK_BASLAT.cmd`** dosyasını günceller.
5. Size 3 seçenek sunar:
   - **`[1]` Bu modu ŞİMDİ başlat:** GoodbyeDPI hemen çalışır ve Discord açılır.
   - **`[2]` Windows Hizmeti Olarak Kur:** Bilgisayar her açıldığında otomatik başlar.
   - **`[3]` Sadece dosyayı kaydet ve çık.**

---

## 🔬 Teknik Açıklama: Neden Sadece Mod 5 Çalışıyor?

KYK / GSB Wi-Fi ağlarında klasik yöntemlerin çalışmayıp Mod 5'in çalışmasının teknik sebepleri:

1. **Stateful TCP Reassembly (Durumlu Akış Birleştirme):**
   Yurt omurgasındaki DPI kutuları akıllı belleğe sahiptir. Düz paket parçalama (`-e 2` veya SNI ofseti) yapıldığında DPI ilk parçayı belleğe alır, ikinci parçayı bekler. Akışı birleştirdiğinde `discord.com` SNI'ını yakalar ve bağlantıyı sıfırlar (`TLS Reset`).

2. **TTL 5 Sahte Paket Zehirlemesi (Mod -5):**
   - GoodbyeDPI gerçek istek öncesinde düşük TTL değerine (4 veya 5) sahip sahte bir TCP paketi fırlatır.
   - Bu sahte paket 4-5 router mesafedeki KYK/TTNET DPI cihazına ulaşıp DPI oturum tablosunu zehirler.
   - Sahte paketin yaşam süresi (TTL) bittiği için Discord sunucusuna asla varamaz (yolda yok olur).
   - Hemen ardından gelen gerçek paketler ters sırada (`--reverse-frag`) gönderilir. DPI cihazı bu oturumu zaten işlediğini sandığı için gerçek paketi süzmeden geçirir.

3. **Neden TTL 3 Çalışmıyor?**
   KYK yurt iç ağındaki switch/router sayısı fazladır. `TTL=3` verildiğinde paket henüz DPI cihazına varmadan yurt içi switch'lerde ölür. `TTL=5` ise tam DPI kutusuna ulaşıp orada son bulur.

4. **Neden Mod 7 / 9 (Hatalı Checksum) Çalışmıyor?**
   KYK yurtlarındaki Fortinet / Cisco kurumsal güvenlik duvarları, bozuk sağlama toplamlı paketleri donanım seviyesinde anında **çöpe atar (DROP)**. Bu yüzden internet kilitlenir.

---

## 📁 Proje Dizin Yapısı

```text
GSBDPI/
│── kyk_test.exe                   # C ile derlenmiş bağımsız yerel test ve teşhis aracı
│── kyk_test.cmd                   # Test aracı için toplu iş dosyası
│── KYK_BASLAT.cmd                 # Otomatik üretilen kişisel yurt başlatıcınız
│── 0_gsb_kyk_yeni_mod.cmd         # Yeni KYK Hibrit Modu (--kyk)
│── 1_gsb_kyk_discord.cmd          # Mod -5 TTL 5 Discord başlatıcısı
│── GSB_KYK_REHBER.md              # Ayrıntılı Türkçe rehber
│── blacklist_kyk.txt              # Engelli alan adları listesi
│── service_install_gsb_kyk.cmd    # Windows arka plan hizmeti kurucu
│── service_remove_gsb_kyk.cmd     # Windows arka plan hizmeti kaldırıcı
│── tools/
│   └── kyk_test.c                 # Test aracının C kaynak kodları
│── goodbyedpi_src/                # Şeffaf DoH modülü eklenmiş GoodbyeDPI kaynak kodları
│   ├── src/
│   │   ├── dohproxy.c / .h        # WinHTTP tabanlı şeffaf DNS-over-HTTPS motoru
│   │   └── goodbyedpi.c           # Modifiye edilmiş GoodbyeDPI ana motoru
│   └── build_msvc.cmd             # Visual Studio MSVC derleme betiği
│── x86_64/                        # 64-bit hazır çalıştırılabilir dosyalar ve WinDivert sürücüsü
└── x86/                           # 32-bit hazır çalıştırılabilir dosyalar
```

---

## 🎙️ Discord Ses Kanalları (RTC / WebRTC) Hakkında

> [!NOTE]
> Discord'un metin mesajları, sunucuları, arkadaş listesi, görselleri ve güncellemeleri **TCP 443 (HTTPS)** portunu kullanır ve GoodbyeDPI ile anında açılır.
> 
> Sesli sohbetler dinamik **UDP portları** (50000-65535) üzerinden bağlanır. Birçok KYK yurdunda 80 ve 443 dışındaki tüm UDP portları yurt güvenlik duvarında tamamen engellidir. GoodbyeDPI bir VPN olmadığı için engellenen UDP paketlerini TCP'ye çeviremez.

### Ses Kanallarına Bağlanma Çözümleri:
1. **Discord Web Sürümü:** Tarayıcınızdan (`discord.com/app`) girin. Tarayıcılar UDP engellendiğinde WebRTC bağlantısını TLS/TCP üzerinden kurabilir.
2. **Cloudflare WARP (1.1.1.1):** WARP uygulamasını kurup bağlantıyı TCP/TLS moduna alabilirsiniz.

---

## 📜 Lisans & Teşekkür

- Bu proje [ValdikSS/GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) projesinden çatallanmış (fork) ve Türkiye KYK/GSB ağları için özelleştirilmiştir.
- Apache License 2.0 ile lisanslanmıştır.
