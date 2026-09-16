import UIKit
import google_mobile_ads

/// 스폰서(Firestore sponsors 컬렉션)가 없을 때 대체로 보여줄 네이티브 광고 뷰.
/// AppDelegate가 두 크기로 등록한다 — 전체 크기는 팩토리 ID "listTile"(홈 탭),
/// 압축형은 "listTile_compact"(식단·버스·설정 탭, KnueNativeAdCard의 압축
/// 스폰서 카드와 같은 한 줄짜리 모양 — 그 카드도 이미지가 없어서 압축형도
/// 미디어뷰를 안 쓴다).
///
/// 타입 이름(NativeAd, NativeAdView, MediaView)은 GAD 접두사가 없는
/// 최신 google_mobile_ads Swift API다 — Codemagic 실제 빌드에서
/// "'GADNativeAd' has been renamed to 'NativeAd'" 컴파일 에러로 확인했다
/// (2026-09-16). Interface Builder(xib) 없이 코드로 직접 짰다 — 이 프로젝트는
/// Windows에서 개발하고 Codemagic(macOS 클라우드)에서 빌드하므로, 여기서 xib를
/// 시각적으로 편집·검증할 방법이 없다.
///
/// android/app/.../NativeAdFactoryImpl.kt와 같은 배치로 맞췄다.
class NativeAdFactoryImpl: NSObject, FLTNativeAdFactory {
    private let isCompact: Bool

    init(isCompact: Bool) {
        self.isCompact = isCompact
    }

    func createNativeAd(
        _ nativeAd: NativeAd,
        customOptions: [AnyHashable: Any]? = nil
    ) -> NativeAdView? {
        return isCompact ? buildCompact(nativeAd) : buildFull(nativeAd)
    }

    // MARK: - 전체 크기 (홈 탭)

    private func buildFull(_ nativeAd: NativeAd) -> NativeAdView {
        let adView = baseAdView()

        let badge = badgeLabel()
        let iconView = iconImageView(size: 36)
        let headlineView = headlineLabel(size: 13.5)
        let bodyView = bodyLabel(size: 11.5)

        let mediaView = MediaView()
        mediaView.layer.cornerRadius = 10
        mediaView.clipsToBounds = true

        let ctaButton = ctaButtonView(fontSize: 13)

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
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        adView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: adView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -16),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
            // 구글 네이티브 광고 정책: 비디오 표시에 최소 120x120pt 필요.
            mediaView.heightAnchor.constraint(equalToConstant: 130),
            ctaButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        // 헤드라인과 mediaContent는 모든 네이티브 광고에 항상 존재한다(Google 보장).
        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        adView.mediaView = mediaView
        mediaView.mediaContent = nativeAd.mediaContent

        bindOptionalAssets(
            adView: adView, nativeAd: nativeAd,
            bodyView: bodyView, iconView: iconView, ctaButton: ctaButton
        )

        adView.nativeAd = nativeAd
        return adView
    }

    // MARK: - 압축형 (식단·버스·설정 탭)

    private func buildCompact(_ nativeAd: NativeAd) -> NativeAdView {
        let adView = baseAdView()

        let badge = badgeLabel(fontSize: 8.5)
        let iconView = iconImageView(size: 32)
        let headlineView = headlineLabel(size: 13)
        let bodyView = bodyLabel(size: 11)
        let ctaButton = ctaButtonView(fontSize: 11.5)

        let headlineRow = UIStackView(arrangedSubviews: [badge, headlineView])
        headlineRow.axis = .horizontal
        headlineRow.spacing = 6
        headlineRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [headlineRow, bodyView])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [iconView, textStack, ctaButton])
        mainStack.axis = .horizontal
        mainStack.spacing = 10
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        adView.layer.cornerRadius = 18
        adView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
            mainStack.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -14),
            mainStack.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
        ])

        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView
        // 압축형은 KnueNativeAdCard의 압축 스폰서 카드처럼 이미지를 안 쓴다 —
        // mediaView를 아예 만들지 않는다(Android native_ad_layout_compact.xml과 동일).

        bindOptionalAssets(
            adView: adView, nativeAd: nativeAd,
            bodyView: bodyView, iconView: iconView, ctaButton: ctaButton
        )

        adView.nativeAd = nativeAd
        return adView
    }

    // MARK: - 공용 조각

    private func baseAdView() -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .white
        adView.layer.cornerRadius = 18
        adView.layer.borderWidth = 0.8
        adView.layer.borderColor = UIColor(white: 0.9, alpha: 1).cgColor
        adView.clipsToBounds = true
        return adView
    }

    private func badgeLabel(fontSize: CGFloat = 9.5) -> UILabel {
        let badge = UILabel()
        badge.text = "  AD  "
        badge.font = .boldSystemFont(ofSize: fontSize)
        badge.textColor = UIColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1)
        badge.backgroundColor = UIColor(white: 0.95, alpha: 1)
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        return badge
    }

    private func iconImageView(size: CGFloat) -> UIImageView {
        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = size >= 36 ? 10 : 8
        iconView.backgroundColor = UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1)
        return iconView
    }

    private func headlineLabel(size: CGFloat) -> UILabel {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: size)
        label.numberOfLines = 1
        return label
    }

    private func bodyLabel(size: CGFloat) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: size)
        label.textColor = UIColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1)
        label.numberOfLines = 1
        return label
    }

    private func ctaButtonView(fontSize: CGFloat) -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .boldSystemFont(ofSize: fontSize)
        button.setTitleColor(UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1), for: .normal)
        button.backgroundColor = UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 0.1)
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        // 이 뷰가 직접 터치를 먹으면 SDK가 탭을 못 받는다. 반드시 꺼야 한다.
        button.isUserInteractionEnabled = false
        return button
    }

    /// 본문·아이콘·CTA는 광고에 따라 없을 수 있어 null 체크 후에만 채운다.
    /// (헤드라인·mediaContent와 달리 Google이 항상 보장하지 않는다.)
    private func bindOptionalAssets(
        adView: NativeAdView,
        nativeAd: NativeAd,
        bodyView: UILabel,
        iconView: UIImageView,
        ctaButton: UIButton
    ) {
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
    }
}
