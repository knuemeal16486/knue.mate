package com.knue.knuemate // [수정]

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity: FlutterActivity() {
    private val fullFactoryId = "listTile"
    private val compactFactoryId = "listTile_compact"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            fullFactoryId,
            NativeAdFactoryImpl(layoutInflater, R.layout.native_ad_layout),
        )
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            compactFactoryId,
            NativeAdFactoryImpl(layoutInflater, R.layout.native_ad_layout_compact),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, fullFactoryId)
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, compactFactoryId)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
