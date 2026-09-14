import SwiftUI
import AppKit

/// Apple Human Interface Guidelines (HIG) ve UI_GUIDELINES.md standartlarında tasarım belirteçleri.
public enum DesignTokens {

    /// 8pt tabanlı Spacing / Margin Skalası
    public enum Spacing {
        /// 4pt - İkon ile bitişik etiket arası, çok sıkı gruplamalar
        public static let xs: CGFloat = 4
        /// 8pt - Bir grup içindeki elemanlar arası (örn. rozet ikonu + metni)
        public static let sm: CGFloat = 8
        /// 12pt - İlişkili ama ayrı bileşenler arası
        public static let md: CGFloat = 12
        /// 16pt - Bölüm/panel iç kenar boşluğu (padding)
        public static let lg: CGFloat = 16
        /// 20pt - Panel dış boşlukları, pencere kenar boşlukları
        public static let xl: CGFloat = 20
        /// 24pt - Pencere kenarı ile ilk/son eleman arası ferah boşluk
        public static let xxl: CGFloat = 24
    }

    /// Tutarlı Köşe Yarıçapı Skalası
    public enum CornerRadius {
        /// 6pt - Küçük elemanlar, etiketler, butonlar
        public static let small: CGFloat = 6
        /// 10pt - Kartlar, açılır paneller, bildirim kutuları
        public static let card: CGFloat = 10
        /// 14pt - Büyük kartlar, modal pencereler
        public static let large: CGFloat = 14
    }

    /// Semantik Durum ve Vurgu Renkleri (Neon renkler kesinlikle yasaktır)
    public enum Colors {
        /// Canlı yayın gösterge rengi (sakin sistem kırmızısı)
        public static let liveIndicator = Color.red.opacity(0.9)
        /// Bağlantı durumu açık (sakin sistem yeşili)
        public static let connected = Color.green.opacity(0.85)
        /// Yeniden bağlanıyor / uyarı durumu (sakin sistem turuncusu)
        public static let warning = Color.orange.opacity(0.85)
        /// Hata durumu
        public static let error = Color.red
        /// İkincil sakin durum
        public static let inactive = Color.secondary

        /// Panel ayraç çizgisi
        public static let separator = Color(nsColor: .separatorColor)
        /// Pencere arka planı
        public static let windowBackground = Color(nsColor: .windowBackgroundColor)
        /// Kontrol / Kart arka planı
        public static let controlBackground = Color(nsColor: .controlBackgroundColor)
    }
}
