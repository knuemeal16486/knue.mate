package com.knue.knuemate

import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.NativeAdFactory

/**
 * 스폰서(Firestore sponsors 컬렉션)가 없을 때 대체로 보여줄 네이티브 광고 뷰.
 * MainActivity가 두 크기로 등록한다 — 전체 크기는 팩토리 ID "listTile"(홈 탭),
 * 압축형은 "listTile_compact"(식단·버스·설정 탭, KnueNativeAdCard의 압축
 * 스폰서 카드와 같은 한 줄짜리 모양). 두 레이아웃이 같은 뷰 ID를 쓰므로
 * 클래스 하나로 레이아웃 리소스만 바꿔 끼워 처리한다.
 *
 * 헤드라인·mediaContent는 모든 네이티브 광고에 반드시 있다(Google 보장)지만,
 * 압축형 레이아웃(native_ad_layout_compact.xml)에는 ad_media 뷰 자체가 없다
 * — 그 압축 스폰서 카드도 이미지를 안 써서 맞춘 것이라, 미디어뷰 바인딩은
 * 있을 때만 한다. 본문·아이콘·CTA는 그 외에도 광고에 따라 없을 수 있어
 * null 체크 후에만 채운다.
 */
class NativeAdFactoryImpl(
    private val layoutInflater: LayoutInflater,
    private val layoutResId: Int,
) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val adView =
            layoutInflater.inflate(layoutResId, null) as NativeAdView

        val mediaView = adView.findViewById<View>(R.id.ad_media)
        if (mediaView != null) {
            adView.setMediaView(mediaView as com.google.android.gms.ads.nativead.MediaView)
            adView.mediaView?.setMediaContent(nativeAd.mediaContent)
        }
        adView.setHeadlineView(adView.findViewById(R.id.ad_headline))
        adView.setBodyView(adView.findViewById(R.id.ad_body))
        adView.setCallToActionView(adView.findViewById(R.id.ad_call_to_action))
        adView.setIconView(adView.findViewById(R.id.ad_app_icon))

        (adView.headlineView as TextView).text = nativeAd.headline

        val body = nativeAd.body
        if (body == null) {
            adView.bodyView?.visibility = View.GONE
        } else {
            (adView.bodyView as TextView).text = body
            adView.bodyView?.visibility = View.VISIBLE
        }

        val cta = nativeAd.callToAction
        if (cta == null) {
            adView.callToActionView?.visibility = View.GONE
        } else {
            (adView.callToActionView as Button).text = cta
            adView.callToActionView?.visibility = View.VISIBLE
        }

        val icon = nativeAd.icon
        if (icon == null) {
            adView.iconView?.visibility = View.GONE
        } else {
            (adView.iconView as ImageView).setImageDrawable(icon.drawable)
            adView.iconView?.visibility = View.VISIBLE
        }

        adView.setNativeAd(nativeAd)
        return adView
    }
}
