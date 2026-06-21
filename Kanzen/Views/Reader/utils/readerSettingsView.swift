import SwiftUI

struct readerManagerSettings: View {
    @ObservedObject var readerManager: readerManager
    var body: some View {
        Form{
            Section{
                Picker("Reading Mode",selection: readerManager.$readingModeRaw){
                    ForEach(ReadingMode.allCases.filter(\.isVisibleInSettings)) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
            }
        }
    }
}
