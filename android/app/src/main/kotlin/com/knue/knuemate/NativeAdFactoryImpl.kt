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
 * MainActivity가 팩토리 ID "listTile"로 등록하고, Dart 쪽은
 * lib/ad_service.dart의 NativeAd(factoryId: "listTile")가 이 뷰를 그린다.
 *
 * 헤드라인·mediaContent는 모든 네이티브 광고에 반드시 있다(Google 보장).
 * 나머지(본문·아이콘·CTA)는 없을 수 있어 null 체크 후에만 채운다.
 */
class NativeAdFactoryImpl(private val layoutInflater: LayoutInflater) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val adView =
            layoutInflater.inflate(R.layout.native_ad_layout, null) as NativeAdView

        adView.setMediaView(adView.findViewById(R.id.ad_media))
        adView.setHeadlineView(adView.findViewById(R.id.ad_headline))
        adView.setBodyView(adView.findViewById(R.id.ad_body))
        adView.setCallToActionView(adView.findViewById(R.id.ad_call_to_action))
        adView.setIconView(adView.findViewById(R.id.ad_app_icon))

        (adView.headlineView as TextView).text = nativeAd.headline
        adView.mediaView?.setMediaContent(nativeAd.mediaContent)

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
