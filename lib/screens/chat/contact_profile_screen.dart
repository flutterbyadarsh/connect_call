import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../providers/chat_providers.dart';
import '../../services/auth_service.dart';
import '../../widgets/profile_image.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';
import '../../providers/call_providers.dart';

class ContactProfileScreen extends ConsumerWidget {
  final String targetUserId;
  final String fallbackName;
  final String profileImageUrl;

  const ContactProfileScreen({
    super.key,
    required this.targetUserId,
    required this.fallbackName,
    required this.profileImageUrl,
  });

  void _showNicknameDialog(
    BuildContext context,
    WidgetRef ref,
    String currentNickname,
  ) {
    final TextEditingController controller = TextEditingController(
      text: currentNickname,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Set Private Nickname',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'This nickname will only be visible to you and will not affect the user\'s real name.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nickname',
                  hintText: 'Enter a private alias',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    final currentUserId = ref
                        .read(authServiceProvider)
                        .currentUser
                        ?.uid;
                    if (currentUserId != null) {
                      ref
                          .read(chatRepositoryProvider)
                          .setContactNickname(
                            currentUserId: currentUserId,
                            targetUserId: targetUserId,
                            nickname: controller.text,
                          );
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _startCall(
    BuildContext context,
    WidgetRef ref,
    bool isVideo,
    String currentUserName,
    String currentUserPic,
  ) async {
    try {
      // The atomic check is now in initiateCall

      final channelId = const Uuid().v4();
      final call = await ref
          .read(callRepositoryProvider)
          .initiateCall(
            receiverId: targetUserId,
            channelId: channelId,
            callerName: currentUserName,
            callerPic: currentUserPic,
            isVideo: isVideo,
          );

      if (!context.mounted) return;
      if (isVideo) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                VideoCallScreen(callerName: call.id, agoraChannelId: channelId),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AudioCallScreen(callerName: call.id, agoraChannelId: channelId),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      if (e.toString().contains("user_busy")) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User is busy on another call')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start call: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final smartNameAsync = ref.watch(smartNameProvider(targetUserId));
    final currentUser = ref.watch(authServiceProvider).currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), elevation: 0),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 32),
            Center(
              child: Hero(
                tag: 'profile_$targetUserId',
                child: ProfileImage(
                  imageUrl: profileImageUrl,
                  radius: 70,
                  fallbackWidget: Icon(
                    Icons.account_circle,
                    size: 140,
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            smartNameAsync.when(
              data: (name) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name == 'Unknown' ? fallbackName : name,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.edit,
                      color: Theme.of(context).primaryColor,
                      size: 20,
                    ),
                    onPressed: () => _showNicknameDialog(
                      context,
                      ref,
                      name == 'Unknown' ? fallbackName : name,
                    ),
                  ),
                ],
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => Text(
                fallbackName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'User ID: $targetUserId',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.call,
                  label: 'Audio',
                  onTap: () {
                    if (currentUser != null) {
                      _startCall(
                        context,
                        ref,
                        false,
                        currentUser.name,
                        currentUser.profileImageUrl,
                      );
                    }
                  },
                ),
                _buildActionButton(
                  context,
                  icon: Icons.videocam,
                  label: 'Video',
                  onTap: () {
                    if (currentUser != null) {
                      _startCall(
                        context,
                        ref,
                        true,
                        currentUser.name,
                        currentUser.profileImageUrl,
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
