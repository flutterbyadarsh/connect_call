class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final String about;
  final String profileImageUrl;
  final bool isOnline;
  final bool isBusy;
  final String? fcmToken;
  final DateTime? lastSeen;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.about = "Hey there! I am using ConnectCall.",
    this.profileImageUrl = "",
    this.isOnline = true,
    this.isBusy = false,
    this.fcmToken,
    this.lastSeen,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      about: data['about'] ?? "Hey there! I am using ConnectCall.",
      profileImageUrl: data['profileImageUrl'] ?? '',
      isOnline: data['isOnline'] ?? false,
      isBusy: data['isBusy'] ?? false,
      fcmToken: data['fcmToken'],
      lastSeen: data['lastSeen'] != null
          ? (data['lastSeen'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'about': about,
      'profileImageUrl': profileImageUrl,
      'isOnline': isOnline,
      'isBusy': isBusy,
      'fcmToken': fcmToken,
      'lastSeen': lastSeen,
    };
  }
}
