# v1.4 Geçiş Kılavuzu

Kayıt kapatma + "1 e-posta = 1 cihaz" + Firestore admin listesi geçişi.

> **Sıralama kritiktir.** Aşağıdaki sıra, iki ciddi arızayı önlemek için
> tasarlandı: (a) filoyu App Review süresince oturumsuz bırakmak,
> (b) yönetici cihazları güvenlik kuralıyla kilitlemek.

---

## Neden bu sıra?

İlk düşünülen sıra — *hesapları sil → cihazları temizle → yeni hesaplar →
admin_users → kurallar → 1.4 gönder* — iki yerde kırılıyor:

1. **1.4 en sona bırakılırsa filo ortada kalır.** Eski Auth hesapları silinince
   refresh token'lar geçersizleşir; tüm 1.3 istemcileri ~1 saat içinde çıkış
   yapar ve geri giremez. 1.4 o anda hâlâ *incelemedeyse* uygulama App Review
   boyunca (1-3+ gün, red gelirse daha uzun) tamamen kullanılamaz.
   → **1.4 App Store'da yayında olmalı, sonra hesaplara dokunulmalı.**

2. **admin_users dokümanları oluşmadan kural yayınlanırsa yöneticiler kilitlenir.**
   Yeni `isAdmin()` bu koleksiyonu okur; doküman yoksa yönetici cihazın
   `authorized_devices` yazımı tamamen reddedilir (cihaz kaydolamaz, kırmızı
   liste kilitlenir) ve hiç kimse etkinlik/misafir silemez.

---

## Aşama 0 — Hazırlık

- [ ] Firestore yedeği: `authorized_devices`, `events`, `events/*/guests`,
      `guests_secure`, `admin_red_list_names`
- [ ] Mevcut yönetici e-postalarını ve `isAdmin: true` cihaz dokümanlarını kaydet
- [ ] Yeni hesap listesini hazırla: hangi e-posta kime, hangileri yönetici
- [ ] **1.2/1.3 uyuşmazlığını çöz:** proje dosyası 1.2 diyordu ama yayında 1.3
      vardı. 1.3'ü üreten kopyayı bu depoyla karşılaştır — burada olmayan
      yayınlanmış değişiklikler varsa 1.4 onları geri alır

## Aşama 1 — Firestore hazırlığı (1.3 ve Android yayındayken güvenli)

- [ ] Her yönetici için `admin_users/<küçük-harfli-eposta>` → `{ isAdmin: true }`
      - Eski iki yönetici (`cbsecurity@checkin.com`, `managercb@cbcheckin.com`)
        hâlâ kullanılıyorsa **onları da ekle**
      - **Birazdan oluşturacağın yeni yönetici hesaplarını da ekle**
      - E-posta küçük harf, baş/son boşluksuz olmalı
- [ ] `Firebase/firestore.rules` dosyasını yayınla
      (`firebase deploy --only firestore:rules`)
- [ ] Rules Playground ile doğrula:
      - ✅ İzin: mevcut yönetici cihazın `lastUsedAt` merge yazımı
      - ❌ Ret: yönetici olmayan hesabın `isAdmin: true` yazması
      - ❌ Ret: `device_bindings` dokümanında `deviceId` değiştirme
      - ❌ Ret: `device_bindings` silme
      - ❌ Ret: başkasının bağını okuma

> Bu noktada 1.3 istemcileri normal çalışmaya devam eder: `device_bindings` ve
> `admin_users`'a hiç dokunmazlar, `isAdmin()` ise artık admin_users'tan
> okunduğu için eski yöneticiler (dokümanları oluşturulduysa) çalışmaya devam eder.

## Aşama 2 — 1.4'ü yayınla

- [ ] Arşivle ve App Store Connect'e yükle (sürüm 1.4, build 140)
      - **Yüklemeden önce** App Store Connect → Activity → All Builds'ten 1.3'ün
        gerçek build numarasını doğrula; 140 ondan büyük olmalı
- [ ] TestFlight: en az bir gerçek cihaz + en az bir yönetici hesabıyla dene
- [ ] App Store'a gönder → **"Ready for Sale" bekle**

## Aşama 3 — Android'i güncelle

- [ ] `AppConstants.kt` içindeki `ADMIN_EMAILS` listesini yeni yönetici
      e-postalarıyla güncelle
- [ ] Yeni Android sürümünü yayınla ve dağıt
- [ ] **Öneri:** Android'i de `admin_users` koleksiyonunu okuyacak şekilde
      değiştirin. Aksi halde her yönetici değişikliğinde iki platformda da
      yeni sürüm gerekir — bu geçişin çözmeye çalıştığı sorunun ta kendisi

> Android'de "1 e-posta = 1 cihaz" kısıtı YOKTUR. Aynı kimlik bilgileri
> Android'de kullanılırsa bağ uygulanmaz. Gerekiyorsa Android'e de aynı
> `device_bindings` mantığı eklenmelidir.

## Aşama 4 — Geçiş penceresi (etkinlik olmayan bir zaman)

- [ ] Duyuru: herkes 1.4'e (ve Android kullanıcıları yeni sürüme) güncellesin,
      **internete bağlıyken** bir kez giriş yapsın
- [ ] Yeni Auth hesaplarını oluştur — **eskileri silmeden** (kendini kilitlememek için)
- [ ] Eski Auth hesaplarını sil → tüm 1.3 oturumları ~1 saat içinde kapanır
- [ ] Tüm `authorized_devices` dokümanlarını sil
      (Android yöneticiler de her cihaz tekrar giriş yapana kadar sıfırlanır)
- [ ] Varsa artık `device_bindings` dokümanlarını sil
- [ ] Her kullanıcı için doğrula:
      - `device_bindings/<eposta>` oluştu mu, `deviceId` dolu mu
      - `authorized_devices/<hash>.isAdmin` doğru mu

---

## Günlük işlemler (geçişten sonra)

| İhtiyaç | Yapılacak |
|---|---|
| Yeni kullanıcı | Console → Authentication → hesap oluştur. Başka bir şey gerekmez; ilk girişte cihaza bağlanır |
| Kullanıcı telefon değiştirdi | Console → Firestore → `device_bindings` → e-posta dokümanını **sil**. Kullanıcı yeni cihazdan giriş yapar |
| Yönetici yap | Console → Firestore → `admin_users/<eposta>` → `{ isAdmin: true }`. Kullanıcı tekrar giriş yapmalı |
| Yönetici yetkisini al | `admin_users` dokümanını sil veya `isAdmin: false`. Kullanıcı tekrar giriş yapmalı |
| Kullanıcı şifresini unuttu | Console → Authentication → şifre sıfırla |

**Cihaz sıfırlama talebi geldiğinde:** kullanıcının gördüğü hata mesajı hem bağlı
cihazın hem elindeki cihazın 8 karakterlik kodunu içerir (örn. `A1B2C3D4`).
Telefonda okutup `device_bindings` dokümanındaki `deviceName` ile karşılaştırarak
kimliği doğrulayabilirsiniz.

> Console'a **en az iki kişinin** erişebildiğinden emin olun: bağ sıfırlamanın
> başka yolu yoktur ve etkinlik gecesi gerekebilir.

---

## Davranış özeti

| Durum | Sonuç |
|---|---|
| İlk giriş, internet var | Cihaza bağlanır, çalışır |
| İlk giriş, internet yok | Reddedilir: "İlk cihaz kaydı için internet bağlantısı gerekli" |
| Aynı cihazdan tekrar giriş | Çalışır (`lastSeenAt` tazelenir) |
| İkinci cihazdan giriş | Reddedilir, oturum kapatılır, iki cihaz kodu gösterilir |
| Bağlı cihaz, internet yok | Çalışır (48 saate kadar) |
| 48 saat hiç sunucuya ulaşamama | Oturum kapanır, tekrar giriş istenir |
| Uygulama silinip yeniden kurulur | Aynı cihaz sayılır (Keychain), çalışır |
| Yedekten BAŞKA telefona geri yükleme | Yeni cihaz sayılır → sıfırlama gerekir (bilinçli) |
