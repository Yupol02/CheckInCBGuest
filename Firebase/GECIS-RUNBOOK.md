# v1.5 Geçiş Kılavuzu

Kayıt kapatma + "1 e-posta = 1 cihaz" + Firestore admin listesi geçişi.

> **Sıralama kritiktir.** Aşağıdaki sıra, iki ciddi arızayı önlemek için
> tasarlandı: (a) filoyu App Review süresince oturumsuz bırakmak,
> (b) yönetici cihazları güvenlik kuralıyla kilitlemek.

---

## Neden bu sıra?

İlk düşünülen sıra — *hesapları sil → cihazları temizle → yeni hesaplar →
admin_users → kurallar → 1.5 gönder* — iki yerde kırılıyor:

1. **1.5 en sona bırakılırsa filo ortada kalır.** Eski Auth hesapları silinince
   refresh token'lar geçersizleşir; tüm 1.3 istemcileri ~1 saat içinde çıkış
   yapar ve geri giremez. 1.5 o anda hâlâ *incelemedeyse* uygulama App Review
   boyunca (1-3+ gün, red gelirse daha uzun) tamamen kullanılamaz.
   → **1.5 App Store'da yayında olmalı, sonra hesaplara dokunulmalı.**

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
      yayınlanmış değişiklikler varsa 1.5 onları geri alır

## Aşama 1 — Firestore hazırlığı (1.3 ve Android yayındayken güvenli)

- [ ] Her yönetici için `admin_users/<küçük-harfli-eposta>` → `{ isAdmin: true }`
      - Eski iki yönetici (`cbsecurity@checkin.com`, `managercb@cbcheckin.com`)
        hâlâ kullanılıyorsa **onları da ekle**
      - **Birazdan oluşturacağın yeni yönetici hesaplarını da ekle**
      - E-posta küçük harf, baş/son boşluksuz olmalı
- [ ] `Firebase/firestore.rules` içeriğini Firebase Console → Firestore Database →
      Rules sekmesine yapıştırıp **Publish** edin
      *(CLI ile deploy edilemez: GuestsBackend/firebase.json'da rules tanımlı değil)*
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

## Aşama 2 — 1.5'ü yayınla

- [ ] Arşivle ve App Store Connect'e yükle (sürüm 1.5)
      - Build numarasını CI otomatik verir (`github.run_number`); elle ayarlamayın
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

- [ ] Duyuru: herkes 1.5'e (ve Android kullanıcıları yeni sürüme) güncellesin,
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

## App Store incelemesi için demo hesap

Kayıt ekranı kaldırıldığı için **incelemeci kendi hesabını oluşturamaz**.
App Store Connect'te demo hesap vermezseniz Guideline 2.1 ile reddedilirsiniz.

Ayrıca demo hesap da cihaza bağlanır: uygulama hem iPhone hem iPad'i
desteklediği için incelemeci ikinci cihazda *"başka bir cihaza tanımlı"*
hatası alabilir — yani kendi korumamız incelemeyi reddettirir.

### Gönderimden önce

1. Firebase Console → Authentication → demo hesabı oluşturun
   (örn. `appreview@checkin.com`)
2. Firestore → `device_bindings` → **Add document**
   - Document ID: `appreview@checkin.com`
   - `email` (string): `appreview@checkin.com`
   - `uid` (string): boş bırakabilirsiniz
   - `deviceId` (string): `exempt`
   - `allowMultipleDevices` (**boolean**): `true`
3. App Store Connect → App Review Information → Sign-In Required işaretli,
   kullanıcı adı ve şifreyi girin
4. Notes alanına ekleyin:
   *"Uygulama etkinlik güvenlik personeli içindir; hesaplar organizatör
   tarafından oluşturulur, self-servis kayıt yoktur. Verilen demo hesap
   birden fazla cihazda kullanılabilir."*

### Onay alındıktan sonra

`device_bindings/appreview@checkin.com` dokümanındaki
`allowMultipleDevices` alanını **false** yapın veya dokümanı silin.
Muafiyeti kapatmak için yeni sürüm gerekmez.

> Muafiyet bayrağını yalnızca Console açabilir; güvenlik kuralı istemcinin
> bu alanı yazmasını veya değiştirmesini engeller.

---

## Koleksiyonlar ne işe yarıyor

| Koleksiyon | Kim yazar | Siz ne yaparsınız |
|---|---|---|
| `authorized_devices` | Uygulama | Hiçbir şey — kendiliğinden yönetilir |
| `device_bindings` | Uygulama | Cihaz değişiminde dokümanı **silersiniz** |
| `admin_users` | **Yalnızca siz** | Yönetici ekler/çıkarırsınız |

Uygulamanın yazdığı iki koleksiyona elle müdahale etmeniz gerekmez.
Sizin yönettiğiniz tek yer `admin_users`.

---

## Birini yönetici yapmak (adım adım)

1. Firebase Console → **Firestore Database**
2. `admin_users` koleksiyonu yoksa **Start collection** → ID: `admin_users`
3. **Add document**
4. **Document ID** kutusuna kişinin e-postasını **küçük harfle** yazın —
   örn. `ahmet@checkin.com`
   *(Auto-ID butonuna basmayın; ID e-postanın kendisi olmalı)*
5. **Add field** → Field: `isAdmin` — Type: **boolean** — Value: **true**
6. **Save**
7. Kişi uygulamadan **çıkıp tekrar giriş yapsın** (yetki giriş anında okunur)

**Yönetici yetkisini almak:** aynı dokümanı silin veya `isAdmin` değerini
`false` yapın; kişi tekrar giriş yaptığında yetkisi kalkar.

> Bu doküman kişi hiç giriş yapmamışken de oluşturulabilir — ilk girişinde
> doğrudan yönetici olarak başlar.

### Neden cihaz dokümanına değil de buraya?

v1.3'te `authorized_devices` içindeki `isAdmin` alanını elle `true` yapmak
kalıcı DEĞİLDİ: uygulama her girişte bu alanı koda gömülü e-posta listesine
göre yeniden yazıyor, listede olmayan hesabın yetkisini sessizce `false`
yapıyordu. v1.5'te bu alan artık `admin_users`'tan besleniyor ve
`admin_users` okunamazsa hiç yazılmıyor — yani yetki kazara düşmüyor.

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

---

# v1.6 Geçişi — Geçmiş etkinlikler yalnızca yöneticide

Yönetici olmayan cihazlar artık **yalnızca bugünkü ve gelecekteki** etkinlikleri
(ve onların misafirlerini) görür. Kısıt hem arayüzde hem Firestore kurallarında
uygulanır.

## Nasıl çalışıyor?

`events/<id>.eventDayKey` — yerel günün sıralanabilir tam sayı hâli (`20260831`).
`date` alanı Türkçe metin olduğu için ("25 Ocak 2026") güvenlik kuralları onu
ayrıştıramaz; anahtar bu yüzden ayrıca yazılır.

- **İstemci** yönetici değilse sorguyu daraltır:
  `whereField("eventDayKey", isGreaterThanOrEqualTo: <bugün>)`
- **Kural** aynı sınırı doğrular; misafir alt koleksiyonları üst etkinliğin
  görünürlüğüne bağlanmıştır.

> **Kurallar filtre değildir.** Daraltılmamış bir sorgu, geçmiş tek bir kayıt
> yüzünden tek tek eleme yapmaz — **tüm listeyi** `permission-denied` alır. Sıranın
> kritik olmasının sebebi budur.

## Sıra (bozulursa filo etkinlik listesini kaybeder)

- [ ] **1. Yedek al:** `events` koleksiyonu (alan ekleniyor)
- [ ] **2. Geri doldur** — hem yeni istemcilerden hem kurallardan ÖNCE.
      Yeni istemci sorgusu `eventDayKey` alanına dayandığı için, alanı olmayan
      etkinlikler sorgu sonucuna hiç girmez: geri doldurma yapılmadan 1.6'ya geçen
      yönetici olmayan cihazlar **hiçbir etkinlik göremez**. Eski istemciler bu
      alanı görmezden geldiği için erken doldurmanın hiçbir yan etkisi yoktur.
      ```
      export GOOGLE_APPLICATION_CREDENTIALS=/yol/servis-hesabi.json
      node Firebase/scripts/backfill-event-day-key.js            # kuru çalışma
      node Firebase/scripts/backfill-event-day-key.js --apply
      ```
      Çıktıdaki "tarihi ayrıştırılamayan kayıtlar" listesini gözden geçirin:
      bunlar `date` alanı bozuk etkinliklerdir; "geçmiş" işaretli değillerse
      görünür bırakılır (`99999999`).
- [ ] **3. iOS 1.6'yı yayınla** ve **Ready for Sale** bekle
- [ ] **4. Android'e aynı iki değişikliği uygula ve dağıt:**
      - etkinlik yazan her yere `eventDayKey` alanı (aynı hesaplama)
      - yönetici değilse etkinlik sorgusunu `eventDayKey >= bugün` ile daralt
- [ ] **5. Tüm cihazların güncellendiğini doğrula** (eski sürümde kalan bir cihaz
      6. adımdan sonra etkinlik listesini bomboş görür)
- [ ] **6. Kuralları yayınla:** `firebase deploy --only firestore:rules`
- [ ] **7. Rules Playground ile doğrula:**
      - ✅ İzin: yönetici olmayan hesap, `eventDayKey` bugüne eşit bir etkinliği okur
      - ❌ Ret: yönetici olmayan hesap, geçen aya ait bir etkinliği okur
      - ✅ İzin: yönetici hesap aynı geçmiş etkinliği okur
      - ❌ Ret: yönetici olmayan hesap, geçmiş etkinliğin `eventDayKey` alanını
        ileri tarihe günceller
      - ❌ Ret: yönetici olmayan hesap, geçmiş etkinliğin `guests` kaydını okur

## Sonrasında

| Durum | Sonuç |
|---|---|
| Yönetici olmayan cihaz | Yalnızca bugünkü + gelecekteki etkinlikler; arama da bu kapsamda |
| Yönetici cihaz | Tümü, geçmiş dahil |
| Yönetici bayrağı sonradan gelirse | Liste kendiliğinden genişler; gelmezse aşağı çekip yenileyin |
| Etkinlik alansız oluşturulmuşsa (eski istemci) | Yönetici olmayan cihazlarda görünmez → geri doldurma betiğini tekrar çalıştırın |
| Uygulama gece yarısını açık geçirirse | Dünkü etkinlik listede kalmaz (arayüz filtresi gizler), sorgu ise bir sonraki açılışta/yenilemede tazelenir |

## Bilinçli sınırlar

- **1 gün tolerans.** Kural, sunucu gününden bir gün geriye izin verir; çünkü
  sorgunun alt sınırını cihaz kendi saatinden hesaplar ve saati/zaman dilimi geri
  kalan bir cihaz aksi hâlde **hiçbir** etkinlik göremezdi. Bedeli: kendi
  istemcisini yazan biri yalnızca **dünkü** etkinlikleri görebilir.
- **Yazma kuralları değişmedi.** Geçmiş etkinlikte değişikliği istemci engeller;
  kurala da koymak, gün anahtarı eksik kalmış tek bir kayıtta etkinlik gecesi tüm
  giriş/çıkışı kilitleme riski taşırdı.
- **`collectionGroup(guests)` sorgusu** (tek bir misafiri id ile arayan geri
  düşüş yolu) bu kurallarla çalışmaz — koleksiyon grubu sorguları için
  `match /{path=**}/guests/{guestId}` gerekir ve böyle bir kural üst etkinlik
  kontrolünü baypas ederdi. Bu yol v1.4'te de reddediliyordu, davranış değişmedi.
