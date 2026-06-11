//
//  FloatingSettingsButton.swift
//  Eclipse
//
//  Created on 27/02/26.
//

import SwiftUI

struct FloatingSettingsButton: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                isPresented = true
            }
        }) {
            Image(systemName: "gear")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .applyLiquidGlassBackground(cornerRadius: 22)
        }
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

#if !os(tvOS)
struct FloatingModeSwitchButton: View {
    @AppStorage("showKanzen") private var showKanzen: Bool = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                showKanzen = true
            }
        } label: {
            Image(systemName: "book.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .applyLiquidGlassBackground(cornerRadius: 22)
        }
        .accessibilityLabel("Switch to Reader Mode")
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}
#endif

struct FloatingSettingsOverlay: View {
    @Binding var showingSettings: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .allowsHitTesting(false)
            
            HStack(spacing: 10) {
#if !os(tvOS)
                FloatingModeSwitchButton()
#endif
                FloatingSettingsButton(isPresented: $showingSettings)
            }
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
    }
}
