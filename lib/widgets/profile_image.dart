import 'dart:convert';
import 'package:flutter/material.dart';

class ProfileImage extends StatelessWidget {
  final String imageUrl;
  final double radius;
  final Widget? fallbackWidget;

  const ProfileImage({
    super.key,
    required this.imageUrl,
    this.radius = 28,
    this.fallbackWidget,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    Widget buildContent() {
      if (imageUrl.isEmpty) {
        return fallbackWidget ??
            CircleAvatar(
              radius: radius,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.person,
                size: radius * 1.2,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            );
      }

      if (imageUrl.startsWith('http')) {
        return ClipOval(
          child: Image.network(
            imageUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return CircleAvatar(
                radius: radius,
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).primaryColor,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            (loadingProgress.expectedTotalBytes ?? 1)
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              debugPrint("Image Load Error: $error");
              return fallbackWidget ??
                  CircleAvatar(
                    radius: radius,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    child: Icon(
                      Icons.person,
                      size: radius * 1.2,
                      color: Theme.of(context).primaryColor,
                    ),
                  );
            },
          ),
        );
      } else if (imageUrl.startsWith('data:image')) {
        // Legacy Base64 support
        try {
          final base64String = imageUrl.split(',').last;
          return CircleAvatar(
            radius: radius,
            backgroundImage: MemoryImage(base64Decode(base64String)),
            backgroundColor: Colors.transparent,
          );
        } catch (e) {
          return fallbackWidget ??
              CircleAvatar(
                radius: radius,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: radius * 1.2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
        }
      }

      return fallbackWidget ??
          CircleAvatar(
            radius: radius,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.person,
              size: radius * 1.2,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
    }

    return SizedBox(width: size, height: size, child: buildContent());
  }
}
