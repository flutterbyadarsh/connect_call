import 'package:flutter_riverpod/flutter_riverpod.dart';

class IncomingCallState {
  final String callerName;
  final String callId;
  final String agoraChannelId;
  final bool isVideo;

  IncomingCallState({
    required this.callerName,
    required this.callId,
    required this.agoraChannelId,
    required this.isVideo,
  });
}

class IncomingCallNotifier extends StateNotifier<IncomingCallState?> {
  IncomingCallNotifier() : super(null);

  void setIncomingCall({
    required String callerName,
    required String callId,
    required String agoraChannelId,
    required bool isVideo,
  }) {
    state = IncomingCallState(
      callerName: callerName,
      callId: callId,
      agoraChannelId: agoraChannelId,
      isVideo: isVideo,
    );
  }

  void clearCall() {
    state = null;
  }
}

final incomingCallProvider =
    StateNotifierProvider<IncomingCallNotifier, IncomingCallState?>((ref) {
      return IncomingCallNotifier();
    });
