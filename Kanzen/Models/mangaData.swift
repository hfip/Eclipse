import SwiftUI
import CoreData

struct Manga: Identifiable {
    let id: UUID = UUID()
    let title: String
    let imageURL: String
    let mangaId: String
    var parentModule: ModuleDataContainer?
    
}


// official mangaData
class MangaData: NSManagedObject {
    @NSManaged var sourceId : UUID
    @NSManaged var mangaId : String
    @NSManaged var title: String?
    @NSManaged var imageURL: String?
    @NSManaged var synopsis: String?
    
}
