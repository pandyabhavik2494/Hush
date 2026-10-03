import SwiftUI
import UIKit

/// About Hush: the version, the privacy policy (App Review asks for one inside the app), where
/// artist photos come from, and the credits the Creative Commons licences of the two built-in
/// photos require. Opened by tapping the Hush wordmark in the library header.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("Hush")
                            .font(HushStyle.brandFont(size: 46))
                            .foregroundStyle(HushStyle.gold)
                        Text("A quiet player for the music you own.")
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .foregroundStyle(HushStyle.ink)
                        Text(versionText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(HushStyle.muted)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                    .accessibilityElement(children: .combine)

                    AboutSection(title: "Privacy Policy") {
                        Text("Hush has no accounts, ads, analytics or tracking, and it doesn't collect any personal data. Your music, playlists, favorite artists and listening history stay on this iPhone.")
                        Text("To show artist photos, Hush looks up artist names in the Apple Music catalog and, when Apple Music has no photo, in Deezer's public catalog. Only the artist's name is sent, and the photo is then saved on this iPhone.")
                    }

                    AboutSection(title: "Your Music") {
                        Text("Hush plays the songs in your library that are downloaded to this iPhone, including music bought from the iTunes Store. You can turn its access to your library on or off at any time in Settings.")
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(HushStyle.gold)
                        .buttonStyle(.plain)
                    }

                    AboutSection(title: "Photo Credits") {
                        CreditRow(
                            subject: "KK",
                            work: "KK (124).jpg",
                            author: "Endeshow1",
                            license: "CC BY-SA 3.0",
                            workAddress: "https://commons.wikimedia.org/wiki/File:KK_%28124%29.jpg",
                            licenseAddress: "https://creativecommons.org/licenses/by-sa/3.0/"
                        )
                        CreditRow(
                            subject: "A. R. Rahman",
                            work: "AR Rahman at Premier Futsal Press Meet (cropped).jpg",
                            author: "Sriram Narasimhan",
                            license: "CC BY-SA 4.0",
                            workAddress: "https://commons.wikimedia.org/wiki/File:AR_Rahman_at_Premier_Futsal_Press_Meet_%28cropped%29.jpg",
                            licenseAddress: "https://creativecommons.org/licenses/by-sa/4.0/"
                        )
                        Text("Both via Wikimedia Commons, cropped and resized. Other artist photos come from Apple Music and Deezer. Album artwork comes from your own library.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .background(HushStyle.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(HushStyle.gold)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(HushStyle.paper)
    }
}

/// A titled card of text in the About sheet.
private struct AboutSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(HushStyle.gold)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .font(.system(size: 14))
            .foregroundStyle(HushStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(HushStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(HushStyle.line, lineWidth: 0.5)
        )
    }
}

/// One photo credit in the form the CC BY-SA licences ask for: title, author, licence, with links.
private struct CreditRow: View {
    let subject: String
    let work: String
    let author: String
    let license: String
    let workAddress: String
    let licenseAddress: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(subject)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HushStyle.ink)
            Text("“\(work)” by \(author), \(license)")
            HStack(spacing: 16) {
                if let url = URL(string: workAddress) {
                    Link("View Photo", destination: url)
                }
                if let url = URL(string: licenseAddress) {
                    Link("View License", destination: url)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(HushStyle.gold)
            .tint(HushStyle.gold)
            .padding(.top, 2)
        }
    }
}
