# R8/ProGuard 규칙 — 릴리스 빌드에서 코드 축소·난독화(isMinifyEnabled/
# isShrinkResources)를 켜면서 추가함. 여기 플러그인들은 리플렉션·Gson
# 직렬화·콜백 디스패처를 쓰기 때문에 규칙 없이 켜면 릴리스 빌드에서만
# 조용히 죽는다 — 각 플러그인 공식 문서가 명시적으로 권장하는 규칙.

# flutter_local_notifications: 예약 알림 정보를 Gson으로 직렬화해
# SharedPreferences에 저장한다. 모델 클래스가 벗겨지면 재부팅 후
# 예약 알림 복원이 깨진다.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends com.dexterous.flutterlocalnotifications.models.** { *; }

# workmanager: Dart 콜백 디스패처를 리플렉션으로 찾는다. 백그라운드
# 건물 데이터 업로드(FirebaseSyncService)가 여기 걸려 있다.
-keep class dev.fluttercommunity.workmanager.** { *; }

# home_widget + androidx.glance: 홈 화면 위젯 렌더링.
-keep class es.antonborri.home_widget.** { *; }
-keep class androidx.glance.** { *; }

# Firebase Cloud Messaging 백그라운드 핸들러.
-keep class io.flutter.plugins.firebase.messaging.** { *; }

# Google Mobile Ads — 네이티브 광고 팩토리(NativeAdFactoryImpl 계열)가
# 여기 클래스들을 직접 참조하므로 함께 지킨다.
-keep class com.google.android.gms.ads.** { *; }

# 위 플러그인들이 공통으로 쓰는 Gson: 모델 필드명이 곧 JSON 키라
# 최소화되면 역직렬화가 깨진다.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keepclassmembers enum * { *; }
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
