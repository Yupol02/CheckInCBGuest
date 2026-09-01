#!/usr/bin/env node
/**
 * v1.6 geri doldurma: events/<id>.eventDayKey
 * ============================================================================
 *
 * Güvenlik kuralı ve istemci sorgusu artık `eventDayKey` alanını okuyor
 * (20260831 gibi sıralanabilir tam sayı). Alanı OLMAYAN bir etkinlik, yönetici
 * olmayan cihazlarda hiç görünmez — bu yüzden kurallar yayınlanmadan ÖNCE tüm
 * mevcut dokümanlar doldurulmalıdır.
 *
 * Anahtar, uygulamadaki `Event.dayKey` ile BİREBİR aynı mantıkla üretilir:
 *   - "25 Ocak 2026"  -> 20260125
 *   - ayrıştırılamayan tarih + status PAST -> 0          (görünmez)
 *   - ayrıştırılamayan tarih + diğer       -> 99999999   (görünür kalır)
 * Son iki kural bilinçlidir: tarihi bozuk tek bir kayıt yüzünden etkinlik
 * sessizce kaybolmasın diye "geçmiş" işaretli olmayanlar görünür bırakılır.
 *
 * KULLANIM — A) Google Cloud Shell (önerilir: kurulum ve anahtar dosyası gerektirmez)
 *   console.cloud.google.com → sağ üstteki terminal simgesi → doğru proje seçili olmalı
 *   Menü (⋮) → "Upload" ile bu dosyayı yükleyin, sonra:
 *     npm i firebase-admin
 *     node backfill-event-day-key.js
 *     node backfill-event-day-key.js --apply
 *   Kimlik doğrulama Cloud Shell'in oturumundan gelir; ayrıca bir şey gerekmez.
 *
 * KULLANIM — B) Kendi bilgisayarınız
 *   npm i firebase-admin
 *   export GOOGLE_APPLICATION_CREDENTIALS=/yol/servis-hesabi.json
 *
 *   node backfill-event-day-key.js                # kuru çalışma (hiçbir şey yazmaz)
 *   node backfill-event-day-key.js --apply        # eksik alanları yazar
 *   node backfill-event-day-key.js --apply --force  # farklı olan mevcut değerleri de düzeltir
 *
 * Betik yeniden çalıştırılabilir (idempotent). Kurallar yayınlandıktan sonra da
 * onarım aracı olarak kullanılabilir: eski bir istemci alansız etkinlik
 * oluşturursa bu betik onu tekrar görünür hâle getirir.
 */

'use strict';

// Modüler giriş noktaları: `require('firebase-admin').credential` firebase-admin 13
// altında tanımsız gelebiliyor; bu iki alt yol her sürümde çalışır.
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const APPLY = process.argv.includes('--apply');
const FORCE = process.argv.includes('--force');
const BATCH_LIMIT = 400;

const UNKNOWN_DATE_DAY_KEY = 99999999; // Event.unknownDateDayKey
const OLDEST_DAY_KEY = 0;              // Event.oldestDayKey

const TURKISH_MONTHS = {
  ocak: 1, subat: 2, mart: 3, nisan: 4, mayis: 5, haziran: 6,
  temmuz: 7, agustos: 8, eylul: 9, ekim: 10, kasim: 11, aralik: 12,
};

/** Türkçe harfleri sadeleştirip küçültür: "AĞUSTOS" -> "agustos". */
function foldTurkish(text) {
  return String(text)
    .replace(/İ/g, 'i').replace(/I/g, 'i').replace(/ı/g, 'i')
    .replace(/Ş/g, 's').replace(/ş/g, 's')
    .replace(/Ğ/g, 'g').replace(/ğ/g, 'g')
    .replace(/Ü/g, 'u').replace(/ü/g, 'u')
    .replace(/Ö/g, 'o').replace(/ö/g, 'o')
    .replace(/Ç/g, 'c').replace(/ç/g, 'c')
    .toLowerCase();
}

/** "25 Ocak 2026" -> 20260125; ayrıştırılamazsa null. */
function parseDayKey(dateText) {
  if (typeof dateText !== 'string') return null;
  const parts = foldTurkish(dateText).trim().split(/\s+/);
  if (parts.length !== 3) return null;

  const day = Number(parts[0]);
  const month = TURKISH_MONTHS[parts[1]];
  const year = Number(parts[2]);
  if (!Number.isInteger(day) || day < 1 || day > 31) return null;
  if (!month) return null;
  if (!Number.isInteger(year) || year < 2000 || year > 2999) return null;

  return year * 10000 + month * 100 + day;
}

function expectedDayKey(data) {
  const parsed = parseDayKey(data.date);
  if (parsed !== null) return parsed;
  return String(data.status).toUpperCase() === 'PAST' ? OLDEST_DAY_KEY : UNKNOWN_DATE_DAY_KEY;
}

async function main() {
  // Cloud Shell'de proje kimliği ortam değişkeninden gelir; yerelde servis hesabı
  // dosyasının içindeki proje kullanılır.
  initializeApp({
    credential: applicationDefault(),
    projectId: process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT || undefined,
  });
  const db = getFirestore();

  const snapshot = await db.collection('events').get();
  console.log(`Toplam etkinlik: ${snapshot.size}`);

  const missing = [];
  const mismatched = [];
  const unparsed = [];
  let alreadyCorrect = 0;

  const skipped = [];

  snapshot.forEach((doc) => {
    const data = doc.data();

    // Silinmiş ya da hem tarihi hem başlığı olmayan kayıtlar ATLANIR.
    // Bunlar uygulamada zaten görünmüyor (doğrulayıcı başlıksız kaydı eler, silinmişler
    // filtrelenir). Anahtar yazsaydık `99999999` ile "sonsuza dek görünür" işaretlenip
    // yönetici olmayan her cihazın sorgusuna gereksiz yere girerlerdi.
    if (data.deleted === true || (!data.date && !data.title)) {
      skipped.push({ id: doc.id, deleted: data.deleted === true, keys: Object.keys(data).join(',') });
      return;
    }

    const expected = expectedDayKey(data);
    const current = data.eventDayKey;

    if (parseDayKey(data.date) === null) {
      unparsed.push({ id: doc.id, date: data.date, title: data.title, expected });
    }

    if (typeof current !== 'number') {
      missing.push({ id: doc.id, expected, title: data.title, date: data.date });
    } else if (current !== expected) {
      mismatched.push({ id: doc.id, current, expected, title: data.title, date: data.date });
    } else {
      alreadyCorrect += 1;
    }
  });

  console.log(`  atlanan     : ${skipped.length}   (silinmiş / tarihi ve başlığı boş)`);
  console.log(`  zaten doğru : ${alreadyCorrect}`);
  console.log(`  eksik       : ${missing.length}`);
  console.log(`  farklı      : ${mismatched.length}   ${FORCE ? '(--force ile düzeltilecek)' : '(dokunulmayacak)'}`);

  if (skipped.length) {
    console.log('\nAtlanan kayıtlar:');
    skipped.forEach((e) => console.log(`  - ${e.id} | deleted=${e.deleted} | alanlar: ${e.keys}`));
  }

  if (unparsed.length) {
    console.log('\nTarihi ayrıştırılamayan kayıtlar (elle kontrol edin):');
    unparsed.forEach((e) => console.log(`  - ${e.id} | date="${e.date}" | "${e.title}" -> ${e.expected}`));
  }

  const targets = FORCE ? missing.concat(mismatched) : missing;
  if (!targets.length) {
    console.log('\nYazılacak kayıt yok.');
    return;
  }

  console.log('\nYazılacak kayıtlar:');
  targets.forEach((e) => {
    const from = e.current === undefined ? '(yok)' : e.current;
    console.log(`  - ${e.id} | "${e.title}" | ${e.date} | ${from} -> ${e.expected}`);
  });

  if (!APPLY) {
    console.log('\nKURU ÇALIŞMA — hiçbir şey yazılmadı. Uygulamak için: --apply');
    return;
  }

  let written = 0;
  for (let i = 0; i < targets.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const entry of targets.slice(i, i + BATCH_LIMIT)) {
      batch.set(db.collection('events').doc(entry.id), { eventDayKey: entry.expected }, { merge: true });
    }
    await batch.commit();
    written += Math.min(BATCH_LIMIT, targets.length - i);
    console.log(`  ${written}/${targets.length} yazıldı`);
  }

  console.log('\nTamamlandı.');
}

main().catch((error) => {
  console.error('HATA:', error);
  process.exitCode = 1;
});
