import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../core/theme/app_theme.dart';

class UserTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;

  const UserTile({
    super.key,
    required this.user,
    required this.onAudioCall,
    required this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: user.profileImageUrl.isNotEmpty
            ? MemoryImage(base64Decode(user.profileImageUrl.split(',').last))
            : null,
        child: user.profileImageUrl.isEmpty
            ? Text(
                user.name.isNotEmpty ? user.name.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(fontSize: 24, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
              )
            : null,
      ),
      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: user.isOnline ? AppTheme.secondaryColor : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(user.isOnline ? 'Online' : 'Offline', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CallButton(icon: Icons.call, color: const Color(0xFF007AFF), onTap: onAudioCall),
          const SizedBox(width: 12),
          _CallButton(icon: Icons.videocam, color: const Color(0xFF5E5CE6), onTap: onVideoCall),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CallButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
