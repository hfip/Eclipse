import Foundation

struct LibraryItem: Codable, Identifiable {
    var id: Int { searchResult.id }
    let searchResult: TMDBSearchResult
    var dateAdded: Date = Date()
}
