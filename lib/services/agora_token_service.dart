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
          .timeout(const Duration(seconds: 3));

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
      // Fallback to empty token so Agora engine can still initialize (if App is in testing mode)
      return {'token': '', 'appId': ''};
    }
  }
}
