import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'meal_rating_service.dart';
import 'ui_utils.dart';

/// 식사시간 종료 10분 전, 아직 별점을 안 남겼으면 "식사하셨나요?" 팝업을
/// 한 번 띄운다. 하루 중 같은 끼니에 대해 두 번 뜨지 않는다(별점을 남겼든,
/// "안 먹었어요"를 눌렀든, 그냥 닫았든 — 팝업이 한 번 떴다는 사실 자체를
/// 로컬에 기록한다).
///
/// RootNavigationScreen이 주기적으로 [maybeShow]를 불러준다. 여기서는 조건만
/// 확인하고 실제로 뜰지 말지, 뭘 보여줄지는 이 파일이 전부 처리한다.
class MealReminder {
  MealReminder._();

  static String _shownKey(MealSource source, MealType type, DateTime date) {
    final dateStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    return "meal_reminder_shown_${source.name}_${type.stdKey}_$dateStr";
  }

  /// 지금 시각 + 사용자 기본 식당 기준으로 조건에 맞으면 팝업을 띄운다.
  /// 조건에 안 맞으면 조용히 아무 일도 안 한다 — 매분 불려도 괜찮다.
  static Future<void> maybeShow(BuildContext context) async {
    final source = defaultSourceNotifier.value;
    final now = DateTime.now();
    final type = mealEndingSoonNow(source, now);
    if (type == null) return;

    final prefs = await SharedPreferences.getInstance();
    final shownKey = _shownKey(source, type, now);
    if (prefs.getBool(shownKey) ?? false) return;

    final alreadyRated = await MealRatingService.alreadyRated(
      source: source,
      type: type,
      date: now,
    );
    if (alreadyRated) {
      // 이미 별점을 남겼으면 물어볼 필요가 없다 — 뜬 걸로 표시만 해둔다.
      await prefs.setBool(shownKey, true);
      return;
    }

    // 화면 전환 등으로 비동기 대기 중에 context가 죽었을 수 있다.
    if (!context.mounted) return;

    // 팝업을 "띄운다"는 사실을 먼저 기록 — 다이얼로그가 뜨는 동안 다음 주기
    // 점검이 겹쳐서 두 개가 뜨는 일을 막는다.
    await prefs.setBool(shownKey, true);

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MealReminderDialog(source: source, type: type),
    );
  }
}

class _MealReminderDialog extends StatefulWidget {
  final MealSource source;
  final MealType type;
  const _MealReminderDialog({required this.source, required this.type});

  @override
  State<_MealReminderDialog> createState() => _MealReminderDialogState();
}

class _MealReminderDialogState extends State<_MealReminderDialog> {
  double _rating = 0;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);

    // 팝업이 닫히면서 토스트를 띄우므로 messenger를 미리 잡아 둔다.
    final messenger = ScaffoldMessenger.of(context);

    String? message;
    try {
      message = await MealRatingService.submit(
        source: widget.source,
        type: widget.type,
        date: DateTime.now(),
        rating: _rating,
      );
    } catch (e) {
      // 예전엔 여기에 catch가 없어서, 제출이 한 번 실패하면 팝업이 닫히지
      // 않고 스피너만 계속 돌았다 — 사용자는 "전송이 끝나지 않는다"고 본다.
      debugPrint('MealReminder: 별점 제출 실패: $e');
      message = "별점을 저장하지 못했어요";
    }

    if (!mounted) return;
    Navigator.pop(context);
    // 남겼는지 아닌지 아무 말이 없으면 눌린 건지도 알 수 없다.
    showToastOn(messenger, message ?? "별점 $_rating점 반영되었습니다. 감사합니다 ❤️");
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warm = KnueTokens.warm(isDark);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${widget.type.label} 식사하셨나요?",
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              "드셨다면 별점만 남겨주세요",
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final starValue = index + 1.0;
                IconData icon;
                if (_rating >= starValue) {
                  icon = Icons.star_rounded;
                } else if (_rating >= starValue - 0.5) {
                  icon = Icons.star_half_rounded;
                } else {
                  icon = Icons.star_outline_rounded;
                }
                return GestureDetector(
                  onTapDown: (details) {
                    final tappedLeftHalf = details.localPosition.dx < 15;
                    setState(() {
                      _rating = tappedLeftHalf ? starValue - 0.5 : starValue;
                    });
                  },
                  child: Icon(icon, color: warm, size: 34),
                );
              }),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    child: Text(
                      "안 먹었어요",
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: _rating == 0 || _submitting ? null : _submit,
                    style: FilledButton.styleFrom(backgroundColor: warm),
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text("등록"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
