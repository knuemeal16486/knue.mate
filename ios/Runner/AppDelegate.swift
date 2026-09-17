import Flutter
import UIKit
import flutter_local_notifications // [추가 1]
import workmanager_apple // [수정]
import google_mobile_ads

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // 스폰서(Firestore sponsors 컬렉션)가 없을 때 대체로 보여줄 네이티브 광고 팩토리.
    // Dart 쪽 lib/ad_service.dart의 NativeAd(factoryId: ...)와 짝이다 —
    // 전체 크기(홈 탭)와 압축형(식단·버스·설정 탭) 둘 다 등록한다.
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "listTile",
      nativeAdFactory: NativeAdFactoryImpl(isCompact: false)
    )
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "listTile_compact",
      nativeAdFactory: NativeAdFactoryImpl(isCompact: true)
    )

    // [추가 2] 포그라운드에서도 알림 배너 표시 설정
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
        GeneratedPluginRegistrant.register(with: registry)
    }

    // 워크매니저 플러그인 등록
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
    }

    // [추가] BGTaskScheduler에 Info.plist에 등록한 식별자를 사용하도록 등록 (이 코드가 없으면 앱이 강제종료됨)
    //
    // 주의: 같은 식별자로 BGTaskScheduler.register()를 두 번 부르면 즉시 SIGABRT로
    // 크래시한다 — 실제 프로덕션 크래시 리포트(1.4.0/42)로 확인됨. Workmanager().
    // registerPeriodicTask()는 workmanager_apple 내부에서 BGAppRefreshTaskRequest를
    // submit하므로(registerBGProcessingTask가 다루는 BGProcessingTask 타입이 아님),
    // 식별자당 registerPeriodicTask(withIdentifier:frequency:)만 한 번씩 불러야 한다.
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "meal_widget_update_task", frequency: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "widget_update", frequency: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "knue_club_event_check_task", frequency: NSNumber(value: 2 * 60 * 60))
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "knue_notice_check_task", frequency: NSNumber(value: 2 * 60 * 60))

    // [추가 3] iOS 10 이상에서 알림 센터 대리자 설정 (필요시)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}