import SwiftUI
import CoreText
import UIKit

// MARK: - Font Registration

enum BestiaryFonts {
    static func register() {
        let files = [
            "MirandaSans-Regular",
            "MirandaSans-Medium",
            "MirandaSans-SemiBold",
            "MirandaSans-Bold",
            "Lusitana-Regular",
            "Lusitana-Bold",
        ]
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                #if DEBUG
                print("[BestiaryFonts] Missing: \(name).ttf")
                #endif
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - UIKit nav bar appearance

    static func applyNavigationBarAppearance() {
        let titleFont      = UIFont(name: "Lusitana", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let largeTitleFont = UIFont(name: "Lusitana-Bold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes     = [.font: titleFont]
        appearance.largeTitleTextAttributes = [.font: largeTitleFont]

        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
    }
}

// MARK: - SwiftUI Font Helpers

extension Font {
    // Lusitana — headers
    static var lusitanaLargeTitle: Font { .custom("Lusitana-Bold",    size: 48, relativeTo: .largeTitle) }
    static var lusitanaTitle:      Font { .custom("Lusitana-Bold",    size: 28, relativeTo: .title) }
    static var lusitanaHeadline:   Font { .custom("Lusitana",         size: 17, relativeTo: .headline) }

    // Miranda Sans — content
    static var msTitle2:       Font { .custom("MirandaSans-SemiBold", size: 22, relativeTo: .title2) }
    static var msHeadline:     Font { .custom("MirandaSans-Bold",     size: 17, relativeTo: .headline) }
    static var msBody:         Font { .custom("MirandaSans-Regular",  size: 17, relativeTo: .body) }
    static var msBodyBold:     Font { .custom("MirandaSans-Bold",     size: 17, relativeTo: .body) }
    static var msSubheadline:  Font { .custom("MirandaSans-Regular",  size: 15, relativeTo: .subheadline) }
    static var msCallout:      Font { .custom("MirandaSans-Regular",  size: 16, relativeTo: .callout) }
    static var msCaption:      Font { .custom("MirandaSans-Regular",  size: 12, relativeTo: .caption) }
    static var msCaption2:     Font { .custom("MirandaSans-Regular",  size: 11, relativeTo: .caption2) }
    static var msCaption2Bold: Font { .custom("MirandaSans-Bold",     size: 11, relativeTo: .caption2) }
    static var msFootnote:     Font { .custom("MirandaSans-Regular",  size: 13, relativeTo: .footnote) }
}
