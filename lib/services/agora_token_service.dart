import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class AgoraTokenService {
  static Future<Map<String, String>> getToken(
    String channelName, {
    int uid = 0,
    bool isRetry = false,
  }) async {
    try {
      debugPrint(
        '⏳ [AgoraTokenService] Fetching token for channel: $channelName (isRetry: $isRetry)',
      );
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-south1',
      ).httpsCallable('generateAgoraToken');

      final result = await callable
          .call({'channelName': channelName, 'uid': uid})
          .timeout(const Duration(seconds: 15));

      final token = result.data['token'] as String;
      final appId = result.data['appId'] as String;

      debugPrint(
        '✅ [AgoraTokenService] Agora token fetched successfully for channel: $channelName',
      );
      return {'token': token, 'appId': appId};
    } catch (e) {
      debugPrint('❌ [AgoraTokenService] Error fetching Agora token: $e');

      if (!isRetry) {
        debugPrint('⏳ [AgoraTokenService] Retrying token generation...');
        return await getToken(channelName, uid: uid, isRetry: true);
      }

      debugPrint(
        '⚠️ [AgoraTokenService] Retry failed. Falling back to empty token to prevent crash.',
      );
      // Fallback: return empty token — Agora will reject join but at least
      // the engine won't crash with error 101 (invalid appId).
      // The Firestore status listener will end the call gracefully.
      return {'token': '', 'appId': '99082f23cb0047f8893f5b8ac23d50a7'};
    }
  }
}
