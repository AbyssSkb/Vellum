import SwiftUI

struct AppLanguageObservedView<Content: View>: View {
    @AppStorage(AppPreferenceKeys.appLanguage) private var appLanguage = AppUILanguage.systemDefault().rawValue
    let content: Content

    init(content: Content) {
        self.content = content
    }

    var body: some View {
        content.environment(\.appUILanguage, AppUILanguage.saved(rawValue: appLanguage))
    }
}
