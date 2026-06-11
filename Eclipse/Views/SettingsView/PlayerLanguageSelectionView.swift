//
//  PlayerLanguageSelectionView.swift
//  Eclipse
//
//  Language selection for in-app subtitle and audio preferences
//

import SwiftUI

struct PlayerLanguageSelectionView: View {
    let title: String
    @Binding var selectedLanguage: String
    @Environment(\.dismiss) private var dismiss
    
    let languages: [(code: String, name: String)] = [
        ("eng", "English"),
        ("jpn", "Japanese"),
        ("zho", "Chinese"),
        ("kor", "Korean"),
        ("spa", "Spanish"),
        ("fra", "French"),
        ("deu", "German"),
        ("ita", "Italian"),
        ("por", "Portuguese"),
        ("rus", "Russian"),
        ("tha", "Thai"),
        ("ara", "Arabic"),
        ("heb", "Hebrew"),
        ("tur", "Turkish"),
        ("pol", "Polish"),
        ("swe", "Swedish"),
        ("dan", "Danish"),
        ("fin", "Finnish"),
        ("nor", "Norwegian"),
        ("nld", "Dutch")
    ]
    
    var body: some View {
        List {
            ForEach(languages, id: \.code) { language in
                HStack {
                    Text(language.name)
                    
                    Spacer()
                    
                    if selectedLanguage == language.code {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedLanguage = language.code
                    dismiss()
                }
            }
            .background(EclipseScrollTracker())
        }
        .navigationTitle(title)
        .eclipseSettingsStyle()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationView {
        PlayerLanguageSelectionView(
            title: "Default Subtitle Language",
            selectedLanguage: .constant("eng")
        )
    }
}
