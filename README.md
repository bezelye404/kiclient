# kiclient

mpv tabanlı, düşük kaynak tüketimli, native macOS Kick.com yayın izleyici ve sohbet istemcisi.

## Özellikler

- Kick kanal slug'ı ile yayını anında başlatma, libmpv + Metal (`gpu-next`) ile donanım hızlandırmalı oynatma.
- Apple VideoToolbox donanım decode'u (`--hwdec=videotoolbox`).
- Gerçek zamanlı sohbet akışı (Pusher WebSocket `v2`, giriş gerektirmez, 100ms batching, 300 mesaj bellek sınırı).
- Kick hesabıyla giriş yaparak sohbete mesaj gönderme (OAuth 2.1 + RFC 7636 PKCE, Keychain saklama).
- **Arka Plan Eko Modu**: Pencere gizlendiğinde veya simge durumundayken video render'ı duraklatılır (`vid=no`), GPU kullanımı %0'a inerken ses ve sohbet bağlantısı kesilmez.
- **HLS Kalite Seçimi**: 1080p60, 720p60, 480p30, 160p ve Otomatik kalite desteği.
- **Dinamik Sohbet Yazı Boyutu**: 11pt, 13pt ve 15pt ölçeklenebilirlik.
- **Dahili Geliştirici Konsolu (Dev Console)**: Canlı RAM/CPU ölçümü, log filtreleme, panoya kopyalama ve interaktif mpv komut satırı (`⌘D`).
- Rekor düzeyde düşük RAM ayak izi: Boşta ~105 MB, 1080p oynatımda ~135 MB RSS (bkz. `PERFORMANCE.md`).

## Gereksinimler

- macOS 14.0+ (Metal, Swift Concurrency ve `ASWebAuthenticationSession`).
- Xcode 15+.
- XcodeGen (`brew install xcodegen`).
- [Homebrew](https://brew.sh) ile kurulmuş `mpv` (geliştirme aşamasında dylib kaynağı):

  ```bash
  brew install mpv
  ```

- Bir Kick Developer App (OAuth test etmek için): `kick.com/settings/developer` üzerinden client ID alınmalı.

## Kurulum (Geliştirme)

```bash
git clone <repo-url>
cd kiclient
xcodegen generate
open kiclient.xcodeproj
```

libmpv linki ve bridging header ayarları için `ARCHITECTURE.md` → "mpv Entegrasyonu" bölümüne bakın.

OAuth için `.env` benzeri bir gizli dosya kullanılmaz; client ID Ayarlar ekranından girilir ve token'lar yalnızca macOS Keychain üzerinde saklanır.

## Build & Çalıştırma

```bash
xcodebuild -project kiclient.xcodeproj -scheme kiclient -configuration Debug build
```

veya doğrudan Xcode üzerinden ⌘R.

## Dağıtım Notu

libmpv dylib'inin uygulama paketine gömülmesi, code signing ve notarization gerektirir (App Store dışı dağıtım dahi). Detaylar için `ARCHITECTURE.md` → "Riskler" bölümü.

## Proje Dokümanları

Bu proje agent-destekli geliştirme için yapılandırılmıştır. Sırasıyla:

- [`AGENTS.md`](./AGENTS.md) — ajan davranış kuralları (önce bu okunmalı)
- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — sistem tasarımı
- [`KICK_API_NOTES.md`](./KICK_API_NOTES.md) — Kick API/WS detayları
- [`DECISIONS.md`](./DECISIONS.md) — mimari kararlar
- [`PERFORMANCE.md`](./PERFORMANCE.md) — performans hedefleri ve ölçümler
- [`TESTING.md`](./TESTING.md) — test stratejisi
- [`ROADMAP.md`](./ROADMAP.md) — fazlı geliştirme planı
- [`CHANGELOG.md`](./CHANGELOG.md) — değişiklik günlüğü

## Lisans

Belirlenmedi — proje sahibi tarafından eklenecek.
