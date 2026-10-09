# GSB / KYK Yurt İnterneti İçin GoodbyeDPI ve Discord Kullanım Rehberi

Bu proje, Türkiye'deki üniversite ve Kredi Yurtlar Kurumu (KYK / GSB) yurtlarında kullanılan kurumsal internet altyapısında (GSB Wi-Fi) ve Türk Telekom hatlarında **GoodbyeDPI** ile Discord ve engelli siteleri sorunsuz şekilde çalıştırmanız için geliştirilmiş özel bir sürümdür.

---

## ⚡ 1. ADIM: Otomatik Test Aracı (`kyk_test.exe`) ⭐ [EN KOLAY YÖNTEM]

Farklı KYK yurtlarında ve illerde güvenlik duvarı (Firewall / DPI) yapılandırmaları farklılık gösterebilir. Tek tek mod denemekle uğraşmamak için projeye **bağımsız C ile derlenmiş küçük bir yerel test aracı (`kyk_test.exe`)** eklenmiştir.

### Nasıl Kullanılır?
1. Klasördeki **`kyk_test.exe`** veya **`kyk_test.cmd`** dosyasına çift tıklayın (araç yönetici iznini otomatik ister).
2. Araç sırasıyla:
   - Yurdunuzun DNS zehirlemesi ve DNS gaspı (hijack) yapıp yapmadığını analiz eder.
   - HTTPS DoH (Cloudflare / Google) erişim durumunu kontrol eder.
   - Farklı DPI atlatma stratejilerini (KYK modu, Mod -5, TTL 5, TTL 3, SNI bölme, Mod -9 vb.) arka planda canlı test eder.
   - Yurt giriş portalı (`wifi.gsb.gov.tr`) ve normal sitelerin bozulup bozulmadığını denetler.
   - Yurdunuz için **en hızlı ve çalışan modu** seçer.
3. Test sonunda otomatik olarak **`KYK_BASLAT.cmd`** dosyasını günceller ve size 3 seçenek sunar:
   - **[1] Bu modu ŞİMDİ başlat ve GoodbyeDPI'ı çalışır durumda bırak** (Tek tıkla hemen internete girersiniz)
   - **[2] Windows Hizmeti (Service) olarak kur** (Bilgisayar her açıldığında otomatik başlar)
   - **[3] Sadece KYK_BASLAT.cmd dosyasını hazırla ve çık**

---

## 🔬 Teknik Açıklama: Neden SADECE Mod 5 Çalıştı? Diğerlerinin Çalışmaması Normal mi?

**Evet, kesinlikle çok normaldir!** KYK / GSB Wi-Fi ve Türk Telekom altyapısının çalışma prensibi gereği diğer modların çalışmaması teknik olarak beklenen bir durumdur:

### 1. Neden Mod 1, 2, 3, 4 ve Düz Parçalama (SNI Bölme) ÇALIŞMIYOR?
- **Stateful TCP Reassembly (Durumlu Akış Birleştirme):** Türk Telekom omurgasında ve GSB yurtlarında kullanılan DPI cihazları (Allot, Sandvine/Procera vb.) akıllı bellek tamponlarına sahiptir.
- Siz paketi sadece ikiye böldüğünüzde (`-e 2` veya SNI ofseti): DPI cihazı ilk parçayı belleğe alır, ikinci parça gelene kadar bekler. İki parçayı birleştirir (reassemble), içinde `discord.com` olduğunu görür ve anında bağlantıyı kesen `TLS Reset (RST)` paketi yollar!
- Sahte paket (fake packet) göndermeyen hiçbir yöntem bu birleştirmeyi aşamaz.

### 2. Neden Mod 5 (`-5 -q` veya `-5 --set-ttl 5`) ÇALIŞIYOR?
- **TTL Aldatmacası ve DPI Zehirleme (Cache Poisoning):**
  1. Mod 5, gerçek Discord bağlantısı öncesinde içi çöp veriyle dolu **sahte bir TCP paketi** üretir.
  2. Bu sahte paketin **TTL (yaşam süresi) değerini 4 veya 5** olarak ayarlar.
  3. Paket yurdunuzdan çıkar, 4-5 router mesafedeki TTNET/GSB DPI cihazına varır.
  4. DPI cihazı "Bu bağlantı başladı" diyerek akış tablosunu (state table) sahte veriyle doldurur ve oturumu kapatır.
  5. Sahte paketin TTL hakkı dolduğu için Discord sunucusuna **asla varamaz** (yolda yok olur), yani Discord sunucusunun kafası karışmaz.
  6. Hemen ardından GoodbyeDPI gerçek ClientHello paketini **ters sırada (`--reverse-frag`)** yollar.
  7. DPI kutusu o oturumu zaten işlediğini sandığı için gerçek paketi denetlemeden geçirir ve Discord anında açılır!

### 3. Neden TTL 3 ÇALIŞMADI?
- KYK yurt içi ağları büyüktür: Odanızdaki Access Point -> Kat Switch'i -> Yurt Ana Router'ı -> TTNET Gateway'i.
- Paket daha yurt binasından çıkmadan 3 hop harcanır. `TTL=3` verildiğinde sahte paket DPI cihazına varamadan yurdun iç ağında ölür; DPI cihazı aldatılamadığı için engel devam eder. `TTL=5` ise tam DPI kutusuna varıp orada son bulur.

### 4. Neden Mod 7, 8 ve 9 (Hatalı Checksum) ÇALIŞMIYOR?
- Mod 7, 8 ve 9 sahte paketi sunucuya ulaştırmamak için bozuk TCP Checksum kullanır.
- Ancak KYK yurtlarındaki Fortinet / Cisco güvenlik duvarları, bozuk checksum gördüğü tüm paketleri donanım seviyesinde anında **çöpe atar (DROP)**. Bu yüzden internet kilitlenir ve zaman aşımı oluşur.

### 5. Neden Dahili DoH (--doh) Şart?
- GSB Wi-Fi, bilgisayarınızda hangi DNS ayarlı olursa olsun UDP 53 portundaki tüm DNS isteklerini yakalayıp kendi sansürlü sunucusuna (`195.175.254.2`) yönlendirir (DNS Hijacking).
- Geliştirdiğimiz dahili **şeffaf DoH motoru**, tüm DNS sorgularını HTTPS tüneli üzerinden şifreli çözerek bu engeli kökten aşar.

---

## 🚀 2. ADIM: Manuel Başlatıcılar

Eğer testi çalıştırmadan doğrudan bağlanmak isterseniz:

### Yeni KYK Modu (`0_gsb_kyk_yeni_mod.cmd` veya `--kyk`) ⭐ [EN YENİ]
- **Özellikleri:**
  - Mod 5'in kanıtlanmış TTL 5 sahte paket ve ters parçalama motorunu kullanır.
  - Dahili Şeffaf DoH (`--doh`) içerir (`hosts` dosyasını değiştirmeye gerek kalmaz).
  - `wifi.gsb.gov.tr`, `kyk.gov.tr`, `turkiye.gov.tr`, `edevlet.gov.tr`, `meb.gov.tr`, `osym.gov.tr` gibi kurumsal alan adları beyaz listededir, giriş sayfası asla kopmaz.
  - QUIC protokolünü engeller (Discord ses bağlantısı TCP fallback ile stabil kalır).

### Mod 1: Klasik TTL 5 Modu (`1_gsb_kyk_discord.cmd`)
- Parametre: `-5 --set-ttl 5 -q --max-payload 1200 --blacklist blacklist_kyk.txt`
- Yalnızca `blacklist_kyk.txt` dosyasındaki siteleri hedefler.

---

## 🔧 3. ADIM: Windows Hizmeti Olarak Kurma (Otomatik Başlatma)

Her seferinde elle pencere açmak istemiyorsanız:
1. **`service_install_gsb_kyk.cmd`** dosyasına sağ tıklayıp **"Yönetici Olarak Çalıştır"** deyin (veya `kyk_test.exe` menüsünden 2'yi seçin).
2. Bilgisayar her açıldığında GoodbyeDPI arka planda görünmez bir Windows servisi olarak otomatik başlar.
3. Kaldırmak istediğinizde **`service_remove_gsb_kyk.cmd`** dosyasını çalıştırmanız yeterlidir.

---

## 🎙️ 4. ADIM: Discord Ses Kanalları (RTC/WebRTC) Bilgisi

> [!IMPORTANT]
> **Teknik Bilgi:** Discord'un metin mesajları, kanallar, sunucu listesi, resimler ve güncellemeleri **TCP 443 (HTTPS)** portu üzerinden çalışır ve GoodbyeDPI ile anında açılır.
> 
> Ancak sesli sohbetler dinamik **UDP portları** (50000-65535) üzerinden bağlanır. Birçok KYK yurdunda 80 ve 443 dışındaki tüm giden UDP portları güvenlik duvarında engellidir. GoodbyeDPI bir tünel/VPN olmadığı için engellenen UDP paketlerini TCP'ye çeviremez.

### Discord Sesine Bağlanma Çözümleri:
1. **Discord Web Sürümü:** Tarayıcınızdan (Chrome/Brave/Edge) `discord.com/app` adresine girin. Tarayıcılar UDP engellendiğinde WebRTC bağlantısını TLS/TCP üzerinden kurabilir.
2. **Cloudflare WARP (1.1.1.1):** WARP uygulamasını kurup bağlantıyı TCP/TLS moduna alabilirsiniz.
3. **SplitCord-Turkey veya Shadowsocks:** Yalnızca Discord ses portlarını TCP tüneline sokan araçları GoodbyeDPI ile birlikte kullanabilirsiniz.
