import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'club_event_service.dart' show posterContentType, posterFileExtension;
import 'sponsor_model.dart';

/// 제휴/광고 Firestore CRUD + Storage 이미지 업로드.
///
/// [KnueNativeAdCard]는 `sponsors` 컬렉션을 직접 실시간 구독해서 보여주므로
/// (오프라인 캐시 없음) 이 서비스는 관리 화면 전용이다 — club_event_service의
/// 캐시 계층은 여기선 필요 없다.
class SponsorService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static const String _collection = 'sponsors';

  static Future<List<Sponsor>> fetchAll() async {
    final snapshot = await _db.collection(_collection).get();
    return snapshot.docs
        .map((d) => Sponsor.fromFirestore(d.id, d.data()))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// id 비었으면 신규 추가, 있으면 갱신.
  static Future<void> upsert(Sponsor sponsor) async {
    final col = _db.collection(_collection);
    if (sponsor.id.isEmpty) {
      await col.add(sponsor.toFirestore());
    } else {
      await col
          .doc(sponsor.id)
          .set(sponsor.toFirestore(), SetOptions(merge: true));
    }
  }

  static Future<void> delete(String id) =>
      _db.collection(_collection).doc(id).delete();

  static Future<void> setActive(String id, bool active) =>
      _db.collection(_collection).doc(id).update({'isActive': active});

  /// 로컬 파일 경로의 이미지를 Storage에 올리고 다운로드 URL 반환. 실패 시 null.
  ///
  /// ⚠️ 포스터 업로드와 같은 이유로 contentType을 직접 넣는다 — putFile은
  /// 메타데이터를 추론해 주지 않는데 storage.rules는 image/* 를 요구한다.
  static Future<String?> uploadImage(String localPath) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = posterFileExtension(localPath);
      final ref = FirebaseStorage.instance.ref('sponsor_images/$ts.$ext');
      await ref.putFile(
        File(localPath),
        SettableMetadata(contentType: posterContentType(localPath)),
      );
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('SponsorService.uploadImage error: $e');
      return null;
    }
  }
}
