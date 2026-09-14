import XCTest
@testable import kiclient

final class KiclientTests: XCTestCase {

    // MARK: - MPV Tests (Faz 1)

    func testMPVConfigurationLowResourceOptions() {
        let config = MPVConfiguration.lowResourceDefault
        let options = config.optionsDictionary()

        // Donanım hızlandırma videotoolbox doğrulaması (ADR / PERFORMANCE kuralı)
        XCTAssertEqual(options["hwdec"], "videotoolbox", "Donanım hızlandırma zorunlu olarak videotoolbox olmalıdır.")

        // Düşük RAM bellek tamponu doğrulaması (32 MiB / 16 MiB)
        XCTAssertEqual(options["demuxer-max-bytes"], "33554432", "Demuxer max bytes 32 MiB olmalıdır.")
        XCTAssertEqual(options["demuxer-max-back-bytes"], "16777216", "Demuxer max back bytes 16 MiB olmalıdır.")

        // Düşük gecikme profili
        XCTAssertEqual(options["profile"], "low-latency", "Canlı yayın için profil low-latency olmalıdır.")
        XCTAssertEqual(options["cache"], "yes", "Önbellek etkin olmalıdır.")
        XCTAssertEqual(options["video-sync"], "audio", "Video senkronizasyonu canlı yayınlarda A/V kaymasını önlemek için audio olmalıdır.")
        XCTAssertEqual(options["framedrop"], "vo", "Kare atlama vo modunda olmalıdır.")
    }

    func testMPVPlaybackStateEquality() {
        XCTAssertEqual(MPVPlaybackState.idle, MPVPlaybackState.idle)
        XCTAssertEqual(MPVPlaybackState.playing, MPVPlaybackState.playing)
        XCTAssertEqual(MPVPlaybackState.paused, MPVPlaybackState.paused)
        XCTAssertEqual(MPVPlaybackState.stopped, MPVPlaybackState.stopped)
        XCTAssertEqual(MPVPlaybackState.loading, MPVPlaybackState.loading)
        XCTAssertNotEqual(MPVPlaybackState.playing, MPVPlaybackState.paused)
        XCTAssertEqual(MPVPlaybackState.error("Test"), MPVPlaybackState.error("Test"))
        XCTAssertNotEqual(MPVPlaybackState.error("A"), MPVPlaybackState.error("B"))
    }

    // MARK: - Channel API Tests (Faz 2)

    func testKickChannelAPIParsingLiveStream() throws {
        let liveJSON = """
        {
            "chatroom": {
                "id": 668,
                "channel_id": 668
            },
            "user": {
                "username": "xQc",
                "profile_pic": "https://files.kick.com/images/user/676/profile.webp"
            },
            "playback_url": "https:\\/\\/fa723fc1b171.playback.live-video.net\\/api\\/video\\/v1\\/channel.DsuAwCgUc9Bh.m3u8?token=xyz",
            "livestream": {
                "session_title": "JUICED GAMING NIGHT",
                "viewer_count": 52140
            }
        }
        """

        let data = try XCTUnwrap(liveJSON.data(using: .utf8))
        let info = try KickChannelAPI.parseChannelJSON(data, slug: "xqc")

        XCTAssertEqual(info.slug, "xqc")
        XCTAssertEqual(info.username, "xQc")
        XCTAssertEqual(info.chatroomId, 668)
        XCTAssertTrue(info.isLive)
        XCTAssertEqual(info.streamTitle, "JUICED GAMING NIGHT")
        XCTAssertEqual(info.viewerCount, 52140)
        XCTAssertEqual(info.playbackURL, "https://fa723fc1b171.playback.live-video.net/api/video/v1/channel.DsuAwCgUc9Bh.m3u8?token=xyz")
    }

    func testKickChannelAPIParsingOfflineStream() throws {
        let offlineJSON = """
        {
            "chatroom": {
                "id": 9999,
                "channel_id": 9999
            },
            "user": {
                "username": "offline_streamer",
                "profile_pic": null
            },
            "playback_url": "https:\\/\\/playback.offline.m3u8",
            "livestream": null
        }
        """

        let data = try XCTUnwrap(offlineJSON.data(using: .utf8))
        let info = try KickChannelAPI.parseChannelJSON(data, slug: "offline_streamer")

        XCTAssertEqual(info.slug, "offline_streamer")
        XCTAssertEqual(info.username, "offline_streamer")
        XCTAssertEqual(info.chatroomId, 9999)
        XCTAssertFalse(info.isLive)
        XCTAssertNil(info.playbackURL, "Offline kanalda playbackURL nil olmalıdır.")
        XCTAssertNil(info.streamTitle)
        XCTAssertNil(info.viewerCount)
    }

    func testKickChannelAPIParsingInvalidJSONThrows() {
        let invalidJSON = "{ \"unexpected\": true }"
        let data = invalidJSON.data(using: .utf8)!

        XCTAssertThrowsError(try KickChannelAPI.parseChannelJSON(data, slug: "test")) { error in
            guard let apiErr = error as? ChannelAPIError,
                  case .decodingFailed = apiErr else {
                XCTFail("Beklenen hata tipi ChannelAPIError.decodingFailed idi, alınan: \(error)")
                return
            }
        }
    }

    // MARK: - Chat Tests (Faz 3)

    func testChatMessageParsingPusherDoubleEncodedJSON() throws {
        let eventName = "App\\Events\\ChatMessageEvent"
        let dataPayload = """
        {
            "id": "msg_12345",
            "chatroom_id": 668,
            "content": "PogChamp harika yayın!",
            "type": "message",
            "created_at": "2026-09-14T22:30:00.000000Z",
            "sender": {
                "id": 8888,
                "username": "Viewer",
                "slug": "viewer",
                "identity": {
                    "color": "#00FF88",
                    "badges": [
                        { "type": "subscriber", "text": "Abone", "count": 12 }
                    ]
                }
            }
        }
        """

        let chatMsg = try XCTUnwrap(ChatMessage.parsePusherData(event: eventName, rawDataString: dataPayload))

        XCTAssertEqual(chatMsg.id, "msg_12345")
        XCTAssertEqual(chatMsg.chatroomId, 668)
        XCTAssertEqual(chatMsg.senderUsername, "Viewer")
        XCTAssertEqual(chatMsg.senderColorHex, "#00FF88")
        XCTAssertEqual(chatMsg.content, "PogChamp harika yayın!")
        XCTAssertEqual(chatMsg.badges.count, 1)
        XCTAssertEqual(chatMsg.badges.first?.type, "subscriber")
    }

    func testChatMessageIgnoreNonChatMessageEvents() throws {
        let internalEvent = "pusher:connection_established"
        let dataPayload = "{\"socket_id\":\"123.456\",\"activity_timeout\":120}"

        let msg = try ChatMessage.parsePusherData(event: internalEvent, rawDataString: dataPayload)
        XCTAssertNil(msg, "Pusher sistem olayları ChatMessage olarak ayrıştırılmamalıdır.")
    }

    func testChatViewModelMaxMessagesCap() {
        let chatVM = ChatViewModel(maxMessages: 10, batchInterval: 0.05)

        for i in 1...15 {
            let msg = ChatMessage(
                id: "id_\(i)",
                chatroomId: 668,
                senderUsername: "User\(i)",
                content: "Message \(i)"
            )
            chatVM.enqueueMessage(msg)
        }

        let expectation = expectation(description: "Flush pending messages")
        chatVM.flushPendingMessages()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(chatVM.messages.count, 10, "300 (veya test limiti 10) mesajdan fazlası tutulmamalı, en eskiler atılmalıdır.")
            XCTAssertEqual(chatVM.messages.first?.id, "id_6", "En eski 5 mesaj kuyruktan düşürülmüş olmalıdır.")
            XCTAssertEqual(chatVM.messages.last?.id, "id_15", "En son eklenen mesaj listenin sonunda yer almalıdır.")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testChatViewModelBatchingCoalescing() {
        let chatVM = ChatViewModel(maxMessages: 100, batchInterval: 10.0) // Uzun süre flush yapmasın

        chatVM.enqueueMessage(ChatMessage(id: "1", chatroomId: 668, senderUsername: "A", content: "M1"))
        chatVM.enqueueMessage(ChatMessage(id: "2", chatroomId: 668, senderUsername: "B", content: "M2"))

        // Flush çağrılmadan önce UI tablosundaki liste boş olmalı (tamponda bekliyor)
        XCTAssertTrue(chatVM.messages.isEmpty, "Mesajlar batch interval gelene kadar tamponda bekletilmelidir.")

        let expectation = expectation(description: "Manual flush")
        chatVM.flushPendingMessages()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(chatVM.messages.count, 2, "Flush yapıldığında tampondaki tüm mesajlar tek seferde aktarılmalıdır.")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - OAuth & Chat Sender Tests (Faz 4)

    func testPKCEVerifierFormatAndRandomness() {
        let v1 = KickAuthManager.generatePKCEVerifier()
        let v2 = KickAuthManager.generatePKCEVerifier()

        XCTAssertFalse(v1.isEmpty)
        XCTAssertFalse(v2.isEmpty)
        XCTAssertNotEqual(v1, v2, "PKCE verifier her seferinde rastgele üretilmelidir.")

        // Base64URL karakter kümesi kontrolü (+ / = olmamalı)
        XCTAssertFalse(v1.contains("+"))
        XCTAssertFalse(v1.contains("/"))
        XCTAssertFalse(v1.contains("="))
        XCTAssertTrue(v1.count >= 43, "PKCE verifier minimum 43 karakter olmalıdır.")
    }

    func testPKCEChallengeRFC7636TestVector() {
        // code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        // SHA-256 base64url = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        let challenge = KickAuthManager.generatePKCEChallenge(from: verifier)
        XCTAssertEqual(challenge, expectedChallenge, "RFC 7636 standart PKCE SHA-256 challenge uyumlu olmalıdır.")
    }

    func testInMemoryKeychainStorageCRUD() throws {
        let keychain = InMemoryKeychainStorage()
        let testKey = "test_token_key"
        let sampleData = "secret_access_token_12345".data(using: .utf8)!

        // 1. Okuma (boşken nil dönmeli)
        XCTAssertNil(keychain.read(key: testKey))

        // 2. Kaydetme & Okuma
        try keychain.save(key: testKey, data: sampleData)
        let retrieved = keychain.read(key: testKey)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved, sampleData)

        // 3. Güncelleme
        let updatedData = "updated_token_67890".data(using: .utf8)!
        try keychain.save(key: testKey, data: updatedData)
        XCTAssertEqual(keychain.read(key: testKey), updatedData)

        // 4. Silme
        try keychain.delete(key: testKey)
        XCTAssertNil(keychain.read(key: testKey))
    }

    func testOAuthTokensExpirationAndSerialization() throws {
        // Yeni üretilmiş token (geçerli)
        let validTokens = OAuthTokens(
            accessToken: "access_token_abc",
            refreshToken: "refresh_token_def",
            tokenType: "Bearer",
            expiresIn: 3600,
            scope: "chat:write user:read channel:read",
            issuedAt: Date()
        )
        XCTAssertFalse(validTokens.isExpired)

        // Süresi dolmuş token (3 saat önce verilmiş)
        let expiredTokens = OAuthTokens(
            accessToken: "expired_token",
            refreshToken: "refresh_xyz",
            tokenType: "Bearer",
            expiresIn: 3600,
            scope: "chat:write",
            issuedAt: Date().addingTimeInterval(-7200)
        )
        XCTAssertTrue(expiredTokens.isExpired)

        // JSON Codable round-trip testi
        let encoded = try JSONEncoder().encode(validTokens)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: encoded)
        XCTAssertEqual(decoded.accessToken, validTokens.accessToken)
        XCTAssertEqual(decoded.refreshToken, validTokens.refreshToken)
        XCTAssertEqual(decoded.tokenType, validTokens.tokenType)
        XCTAssertEqual(decoded.expiresIn, validTokens.expiresIn)
        XCTAssertEqual(decoded.scope, validTokens.scope)
    }

    func testKickChatSenderRejectsEmptyMessage() async {
        let fakeAuth = FakeAuthManager(token: "valid_token")
        let sender = KickChatSender(authManager: fakeAuth)

        do {
            try await sender.sendMessage(content: "   ", broadcasterUserId: 123)
            XCTFail("Boş mesaj gönderimi ChatSendError.emptyMessage fırlatmalıydı.")
        } catch let err as ChatSendError {
            XCTAssertEqual(err, .emptyMessage)
        } catch {
            XCTFail("Beklenmeyen hata: \(error)")
        }
    }

    func testKickChatSenderRejectsUnauthenticated() async {
        let fakeAuth = FakeAuthManager(token: nil) // Giriş yapılmamış
        let sender = KickChatSender(authManager: fakeAuth)

        do {
            try await sender.sendMessage(content: "Merhaba Kick", broadcasterUserId: 123)
            XCTFail("Yetkisiz gönderim ChatSendError.unauthorized fırlatmalıydı.")
        } catch let err as ChatSendError {
            XCTAssertEqual(err, .unauthorized)
        } catch {
            XCTFail("Beklenmeyen hata: \(error)")
        }
    }

    // MARK: - Faz 5 & Faz 6 & Dev Console Tests

    func testAppLoggerCapacityAndLevels() {
        let logger = AppLogger(maxEntries: 5)
        logger.clear()

        for i in 1...10 {
            logger.info(category: .player, "Log entry \(i)")
        }

        XCTAssertEqual(logger.entries.count, 5, "Maksimum log limiti 5 ile sınırlandırılmalıdır.")
        XCTAssertEqual(logger.entries.last?.message, "Log entry 10")
        XCTAssertEqual(logger.entries.first?.message, "Log entry 6")

        logger.clear()
        XCTAssertTrue(logger.entries.isEmpty, "clear() çağrısı tüm logları temizlemelidir.")
    }

    func testAppLoggerLiveMetrics() {
        let ram = AppLogger.getMemoryUsageMB()
        let cpu = AppLogger.getCPUUsagePercentage()

        XCTAssertGreaterThan(ram, 0.0, "Uygulama bellek tüketimi 0'dan büyük olmalıdır.")
        XCTAssertGreaterThanOrEqual(cpu, 0.0, "CPU tüketimi negatif olamaz.")
    }

    func testImageCacheManagerSetGetAndRemove() {
        let cache = ImageCacheManager(totalCostLimitMB: 5, countLimit: 10)
        let sampleURL = URL(string: "https://files.kick.com/badges/sub.png")!
        let image = NSImage(size: NSSize(width: 16, height: 16))

        XCTAssertNil(cache.image(for: sampleURL))

        cache.setImage(image, for: sampleURL)
        XCTAssertNotNil(cache.image(for: sampleURL), "Kaydedilen görsel önbellekten geri okunabilmelidir.")

        cache.removeImage(for: sampleURL)
        XCTAssertNil(cache.image(for: sampleURL), "Silinen görsel önbellekte bulunmamalıdır.")
    }

    func testStreamQualityBitrateMappings() {
        XCTAssertEqual(StreamQuality.auto.maxBitrate, "max")
        XCTAssertEqual(StreamQuality.q1080p.maxBitrate, "8500000")
        XCTAssertEqual(StreamQuality.q720p.maxBitrate, "4500000")
        XCTAssertEqual(StreamQuality.q480p.maxBitrate, "2000000")
        XCTAssertEqual(StreamQuality.q160p.maxBitrate, "500000")
    }
}

// MARK: - Test Doubles

final class FakeAuthManager: AuthManaging, @unchecked Sendable {
    var isAuthenticated: Bool { token != nil }
    var currentTokens: OAuthTokens?
    private let token: String?

    init(token: String?) {
        self.token = token
        if let token = token {
            self.currentTokens = OAuthTokens(
                accessToken: token,
                refreshToken: nil,
                tokenType: "Bearer",
                expiresIn: 3600,
                scope: "chat:write"
            )
        }
    }

    func getValidAccessToken() async throws -> String {
        if let token = token {
            return token
        }
        throw NSError(domain: "KickAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Giriş yapılmamış"])
    }

    func logout() {
        self.currentTokens = nil
    }
}

