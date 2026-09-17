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

    // GeneratedPluginRegistrant.register(with:)가 먼저 돌아야 FLTGoogleMobileAdsPlugin
    // 인스턴스가 registry에 publish된다. registerNativeAdFactory는 그 인스턴스를
    // valuePublishedByPlugin:으로 찾는데, 아직 없으면 조용히 아무 일도 안 하고 YES를
    // 반환한다(플러그인 내부의 NSException이 raise가 아니라 그냥 생성만 되고 버려짐 —
    // 실제 google_mobile_ads-9.0.0 소스로 확인). 그래서 이 순서를 지켜야 한다:
    // register(with:) → registerNativeAdFactory. 원래 코드가 순서를 반대로 해서
    // iOS에서 네이티브 광고가 항상 조용히 실패하고 있었다(Android MainActivity.kt는
    // super.configureFlutterEngine이 먼저라 문제 없었음).
    GeneratedPluginRegistrant.register(with: self)

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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}