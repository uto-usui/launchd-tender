import CoreGraphics

/// Tender のデザイントークン。
///
/// DESIGN.md で定義した spacing / radius / motion を Swift から参照するための最小集合。
/// 派生値は追加せず、6 段階の spacing と 3 段階の radius に固定する。
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
}
