import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class AgoraTokenService {
  static Future<Map<String, String>> getToken(String channelName, {int uid = 0}) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('generateAgoraToken');
      
      final result = await callable.call({
        'channelName': channelName,
        'uid': uid,
      });

      final token = result.data['token'] as String;
      final appId = result.data['appId'] as String;
      
      debugPrint('✅ Agora token fetched for channel: $channelName');
      return {'token': token, 'appId': appId};
    } catch (e) {
      debugPrint('❌ Error fetching Agora token: $e');
      rethrow;
    }
  }
}
