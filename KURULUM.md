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
2. `efetufe-<sürüm>.apk` dosyasını indir.
3. İndirilen dosyaya dokun. Android "bilinmeyen kaynaklardan uygulama yükleme" iznini sorar:
   **Ayarlar → Bu kaynaktan izin ver** (Chrome veya Dosyalar uygulaması için) → geri dön → **Yükle**.
4. Play Protect uyarısı çıkarsa **Yine de yükle** de (uygulama Play Store'da yayınlanmadığı için normal).

Alternatif (USB ile): telefonda Geliştirici seçenekleri → USB hata ayıklama açıkken,
bilgisayarda `adb install efetufe-<sürüm>.apk`.

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
- Kendi müziklerini eklemek için: `docker compose cp <klasör> api:/tmp/muzik` ve
  `docker compose exec api python -m app.cli ingest /tmp/muzik`.
