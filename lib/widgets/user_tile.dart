import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_model.dart';
import 'profile_image.dart';
import '../../providers/chat_providers.dart';
import '../screens/chat/contact_profile_screen.dart';
import '../../services/user_service.dart';

class UserTile extends ConsumerWidget {
  final UserModel user;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;
  final VoidCallback? onMessage;
  final VoidCallback? onLongPress;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback? onToggleSelection;

  const UserTile({
    super.key,
    required this.user,
    required this.onAudioCall,
    required this.onVideoCall,
    this.onMessage,
    this.onLongPress,
    this.isSelecting = false,
    this.isSelected = false,
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final smartNameAsync = ref.watch(smartNameProvider(user.uid));
    final presenceAsync = ref.watch(userPresenceProvider(user.uid));
    final isOnline = presenceAsync.valueOrNull?.isOnline ?? user.isOnline;

    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(
            context,
          ).primaryColor.withValues(alpha: 0.1),
          onTap: () {
            HapticFeedback.lightImpact();
            if (isSelecting) {
              if (onToggleSelection != null) onToggleSelection!();
            } else {
              if (onMessage != null) onMessage!();
            }
          },
          onLongPress: onLongPress == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onLongPress!();
                },
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelecting)
                Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    if (onToggleSelection != null) onToggleSelection!();
                  },
                ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ContactProfileScreen(
                        targetUserId: user.uid,
                        fallbackName: user.name,
                        profileImageUrl: user.profileImageUrl,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      ProfileImage(imageUrl: user.profileImageUrl, radius: 26),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          title: smartNameAsync.when(
            data: (name) => Text(
              name == 'Unknown' ? user.name : name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            loading: () => Text(
              user.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            error: (_, __) => Text(
              user.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: isOnline ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    user.phoneNumber,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onAudioCall,
                icon: const Icon(Icons.call, color: Colors.green),
                tooltip: 'Audio Call',
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onVideoCall,
                icon: const Icon(Icons.videocam, color: Colors.blue),
                tooltip: 'Video Call',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
