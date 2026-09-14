# kiclient

mpv tabanlı, düşük kaynak tüketimli, native macOS Kick.com yayın izleyici ve sohbet istemcisi.

## Özellikler (Hedef)

- Kick kanal slug'ı ile yayını başlatma, libmpv + Metal ile oynatma.
- Donanım hızlandırmalı decode (VideoToolbox).
- Gerçek zamanlı sohbet okuma (Pusher WebSocket, giriş gerektirmez).
- Kick hesabıyla giriş yaparak sohbete yazabilme (OAuth 2.1 + PKCE).
- Düşük RAM/GPU ayak izi (bkz. `PERFORMANCE.md`).

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
