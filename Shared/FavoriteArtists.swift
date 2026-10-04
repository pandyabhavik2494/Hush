import Foundation

/// The artists you've marked as favourites (their normalized ids), remembered between launches.
/// Shown first on the Artists tab on the iPhone and in the Artists section on the Mac.
enum FavoriteArtists {
    private static let defaultsKey = "hush.favoriteArtists"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    static func save(_ ids: Set<String>) {
        UserDefaults.standard.set(ids.sorted(), forKey: defaultsKey)
    }
}
