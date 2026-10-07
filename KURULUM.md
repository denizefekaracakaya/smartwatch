# Efetüfe — Telefona kurulum rehberi

Uygulama müziği bir **sunucudan** çeker. Bu yüzden önce sunucuyu bilgisayarında çalıştırman, sonra
telefondaki uygulamayı o sunucuya bağlaman gerekir. Telefon ile bilgisayar **aynı Wi-Fi ağında** olmalı.

## 1. Sunucuyu başlat (bilgisayarda, Docker ile)

1. Docker Desktop'ı aç.
2. Bilgisayarının ağ adresini öğren: PowerShell'de `ipconfig` → "Wi-Fi" altındaki **IPv4 Address**
   (örnek: `192.168.1.8`).
3. Proje klasöründe (PowerShell) — ilk seferde ayar dosyasını oluştur, sonra başlat:

   ```powershell
   # Bir kez: gizli anahtar + telefonun kullanacağı adres (.env dosyası, git'e eklenmez)
   $key = python -c "import secrets;print(secrets.token_urlsafe(48))"
   Set-Content -Encoding ascii .env "APP_SECRET_KEY=$key`nAPP_PUBLIC_BASE_URL=http://192.168.1.8:8000"

   docker compose up -d --build
   docker compose exec api python -m app.cli seed-demo     # 16 demo parça ekler (bir kez yeterli)
   ```

   Sonraki seferlerde sadece `docker compose up -d` yeterli. Gizli anahtar değişirse tüm oturumlar
   kapanır; bu yüzden `.env` dosyasını sakla.

4. Kontrol: tarayıcıda `http://192.168.1.8:8000/health` → `{"status":"ok"}` görmelisin.
   Doğrulama ve şifre sıfırlama e-postaları `http://localhost:8025` (Mailpit) adresinde görünür.

> Windows ilk seferde "Docker Desktop Backend" için ağ izni sorabilir; **İzin ver** de. Telefon
> sunucuya ulaşamazsa Windows Güvenlik Duvarı'nda 8000 numaralı porta gelen bağlantılara izin ver.

## 2. APK'yı indir ve kur (telefonda)

1. Telefonun tarayıcısında GitHub'daki **Releases** sayfasını aç:
   <https://github.com/denizefekaracakaya/smartwatch/releases/latest>
2. En yeni `efetufe-<sürüm>.apk` dosyasını indir (0.1.0'da çalma hatası vardı; 0.1.1 veya üstünü kullan).
3. İndirilen dosyaya dokun. Android "bilinmeyen kaynaklardan uygulama yükleme" iznini sorar:
   **Ayarlar → Bu kaynaktan izin ver** (Chrome veya Dosyalar uygulaması için) → geri dön → **Yükle**.
4. Play Protect uyarısı çıkarsa **Yine de yükle** de (uygulama Play Store'da yayınlanmadığı için normal).

Alternatif (USB ile): telefonda **Ayarlar → Telefon hakkında → Yapı numarası**'na 7 kez dokun →
**Geliştirici seçenekleri → USB hata ayıklama**'yı aç → telefonu kabloyla bağla → telefonda çıkan
"USB hata ayıklamaya izin ver" sorusuna **İzin ver** de → bilgisayarda:
`adb install -r efetufe-<sürüm>.apk`.

> **0.1.0 / 0.1.1'den 0.1.2'ye geçiş:** 0.1.2'den itibaren uygulama kalıcı bir imza anahtarıyla
> imzalanıyor. Eski sürümler farklı bir anahtarla imzalandığı için **bir kereye mahsus** eski uygulamayı
> kaldırıp yenisini kurman gerekir (hesabın sunucuda durur; sadece tekrar giriş yapar ve sunucu adresini
> yeniden girersin). Sonraki tüm güncellemeler doğrudan üzerine kurulur.

## 3. Uygulamayı sunucuya bağla

1. Uygulamayı aç; giriş ekranının altındaki **Sunucu: …** yazısına dokun.
2. `192.168.1.8:8000` (kendi IP adresin) yaz → **Kaydet**. Adres kalıcı olarak hatırlanır.
3. **Hesap oluştur** → doğrulama e-postasını `http://localhost:8025` (Mailpit) üzerinden aç →
   bağlantıdaki **E-postamı doğrula** düğmesine bas → uygulamada giriş yap.

## Notlar

- Bu test sürümü yerel ağda şifrelenmemiş HTTP bağlantısına izin verir. Herkese açık bir kurulumda
  sunucu HTTPS arkasında çalışmalı ve APK `ALLOW_CLEARTEXT` olmadan derlenmelidir (README → APK).
- AI asistanın Claude ile çalışması için sunucuyu başlatmadan önce `$env:ANTHROPIC_API_KEY` ayarla;
  aksi halde asistan bulanık aramaya geri döner.
- Sunucuyu yalnızca kendin ve ailen için (evdeki ağda) kullan. Telifli müzikleri herkese açık
  yayınlamak hukuken sorun olur.

## 4. Gerçek müzik ekleme

Spotify ve YouTube'dan **ses indirilemez**: Spotify'ın sesi DRM ile korunuyor, iki hizmetin de kuralları
indirmeyi yasaklıyor ve telif hakkı ihlali olur. Bunun yerine sahip olduğun dosyaları sunucuya eklersin.

1. Şarkılarını bir klasöre koy (mp3, m4a, flac, ogg, opus, wav; alt klasörler de olur). Dosyalarda
   etiket (şarkı adı/sanatçı) yoksa adlarını `Sanatçı - Şarkı.mp3` biçiminde ver.
2. Proje klasöründe (PowerShell):

   ```powershell
   .\scripts\add_music.ps1 "D:\Muzik"
   .\scripts\add_music.ps1 "D:\Podcastlar" -Kind podcast
   ```

   Aynı klasörü tekrar eklemek güvenli; aynı dosyalar ikinci kez eklenmez.

Yasal ve ücretsiz müzik kaynakları: kendi satın aldığın dijital albümler (Bandcamp, iTunes vb.), CD'den
aktardıkların, Creative Commons lisanslı müzikler (Jamendo, Free Music Archive, Internet Archive).

## 5. Spotify çalma listelerini aktarma

Listelerin **şarkı adları ve sanatçıları** aktarılır. Sunucuda bulunan şarkılarla aynı adlı çalma listeleri
hesabında oluşturulur. Sunucuda olmayan şarkılar `eksik-sarkilar.csv` dosyasına yazılır; onları 4. adımla
ekleyip aktarımı tekrar çalıştırabilirsin (aynı şarkılar tekrar eklenmez).

**Yol A — Spotify veri indirme (tüm listeler, gizliler dahil, kurulum gerektirmez):**
spotify.com → Hesap → **Gizlilik ayarları** → "Verilerini indir" → **Hesap verileri**'ni seç ve iste.
Birkaç gün içinde e-postayla gelen zip'in içindeki `Playlist1.json` dosyasını kullan:

```powershell
.\scripts\import_playlists.ps1 -Source "C:\Users\deniz\Downloads\Spotify Account Data\Playlist1.json" -User senin@epostan.com
```

Aynı klasördeki `YourLibrary.json` dosyası "Beğenilen Şarkılar" listesini getirir.

**Yol B — Exportify (hemen, tek tek listeler):** <https://exportify.net> adresinde Spotify ile giriş yap →
istediğin listede **Export** → inen `.csv` dosyasını ver:

```powershell
.\scripts\import_playlists.ps1 -Source "C:\Users\deniz\Downloads\yolculuk.csv" -User senin@epostan.com
```

**Yol C — Liste bağlantısıyla (herkese açık listeler):** <https://developer.spotify.com/dashboard>
adresinde ücretsiz bir uygulama oluştur. Redirect URI olarak `http://127.0.0.1:8888/callback` yazabilirsin;
kullanılmıyor ama form istiyor. Uygulamanın **Client ID** ve **Client Secret** değerlerini al:

```powershell
$env:SPOTIFY_CLIENT_ID = "..."; $env:SPOTIFY_CLIENT_SECRET = "..."
.\scripts\import_playlists.ps1 -Source "https://open.spotify.com/playlist/..." -User senin@epostan.com
```

Spotify'ın kendi hazırladığı listeleri (ör. "Today's Top Hits") bu yolla okumak, yeni uygulamalara kapalı.
Onlar için Yol B'yi kullan.

Önce ne eşleşeceğini görmek için komutun sonuna `-DryRun` ekle.
