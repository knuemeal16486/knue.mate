import UIKit
import google_mobile_ads

/// 스폰서(Firestore sponsors 컬렉션)가 없을 때 대체로 보여줄 네이티브 광고 뷰.
/// AppDelegate가 팩토리 ID "listTile"로 등록하고, Dart 쪽은
/// lib/ad_service.dart의 NativeAd(factoryId: "listTile")가 이 뷰를 그린다.
///
/// 타입 이름(GADNativeAd 등)은 googleads-mobile-flutter 공식 저장소의
/// packages/google_mobile_ads/example/ios/Runner/AppDelegate.m을 그대로 따른다
/// (2026-09-15 확인). Interface Builder(xib) 없이 코드로 직접 짰다 — 이 프로젝트는
/// Windows에서 개발하고 Codemagic(macOS 클라우드)에서 빌드하므로, 여기서 xib를
/// 시각적으로 편집·검증할 방법이 없다.
///
/// android/app/.../NativeAdFactoryImpl.kt와 같은 배치(아이콘+제목/설명,
/// 미디어, CTA 버튼)로 맞췄다.
class NativeAdFactoryImpl: NSObject, FLTNativeAdFactory {
    func createNativeAd(
        _ nativeAd: GADNativeAd,
        customOptions: [AnyHashable: Any]? = nil
    ) -> GADNativeAdView? {
        let adView = GADNativeAdView()
        adView.backgroundColor = .white
        adView.layer.cornerRadius = 18
        adView.layer.borderWidth = 0.8
        adView.layer.borderColor = UIColor(white: 0.9, alpha: 1).cgColor
        adView.clipsToBounds = true

        let badge = UILabel()
        badge.text = "  AD  "
        badge.font = .boldSystemFont(ofSize: 9.5)
        badge.textColor = UIColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1)
        badge.backgroundColor = UIColor(white: 0.95, alpha: 1)
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true

        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 10
        iconView.backgroundColor = UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1)

        let headlineView = UILabel()
        headlineView.font = .boldSystemFont(ofSize: 13.5)
        headlineView.numberOfLines = 1

        let bodyView = UILabel()
        bodyView.font = .systemFont(ofSize: 11.5)
        bodyView.textColor = UIColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1)
        bodyView.numberOfLines = 1

        let mediaView = GADMediaView()
        mediaView.layer.cornerRadius = 10
        mediaView.clipsToBounds = true

        let ctaButton = UIButton(type: .system)
        ctaButton.titleLabel?.font = .boldSystemFont(ofSize: 13)
        ctaButton.setTitleColor(UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1), for: .normal)
        ctaButton.backgroundColor = UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 0.1)
        ctaButton.layer.cornerRadius = 12
        // 이 뷰가 직접 터치를 먹으면 SDK가 탭을 못 받는다. 반드시 꺼야 한다.
        ctaButton.isUserInteractionEnabled = false

        let textStack = UIStackView(arrangedSubviews: [headlineView, bodyView])
        textStack.axis = .vertical
        textStack.spacing = 2

        let topRow = UIStackView(arrangedSubviews: [iconView, textStack])
        topRow.axis = .horizontal
        topRow.spacing = 12
        topRow.alignment = .center

        let mainStack = UIStackView(arrangedSubviews: [badge, topRow, mediaView, ctaButton])
        mainStack.axis = .vertical
        mainStack.spacing = 10
        mainStack.setCustomSpacing(10, after: badge)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        adView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: adView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -16),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
            mediaView.heightAnchor.constraint(equalToConstant: 140),
            ctaButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        // 헤드라인과 mediaContent는 모든 네이티브 광고에 항상 존재한다(Google 보장).
        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        adView.mediaView = mediaView
        mediaView.mediaContent = nativeAd.mediaContent

        // 나머지(본문·아이콘·CTA)는 없을 수 있어 null 체크 후에만 채운다.
        if let body = nativeAd.body, !body.isEmpty {
            bodyView.text = body
            bodyView.isHidden = false
        } else {
            bodyView.isHidden = true
        }
        adView.bodyView = bodyView

        if let icon = nativeAd.icon {
            iconView.image = icon.image
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
        adView.iconView = iconView

        if let cta = nativeAd.callToAction, !cta.isEmpty {
            ctaButton.setTitle(cta, for: .normal)
            ctaButton.isHidden = false
        } else {
            ctaButton.isHidden = true
        }
        adView.callToActionView = ctaButton

        adView.nativeAd = nativeAd
        return adView
    }
}
