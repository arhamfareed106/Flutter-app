import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ClientNotificationService {
  static final ClientNotificationService _instance =
      ClientNotificationService._internal();
  factory ClientNotificationService() => _instance;
  ClientNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isInitialized = false;
  StreamSubscription? _messageListener;
  StreamSubscription? _bidListener;
  StreamSubscription? _interventionStatusListener;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    print('Initializing ClientNotificationService...'); // Debug print

    // Local notification setup
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(initSettings);
    print('Local notifications initialized'); // Debug print

    // FCM permissions
    await _firebaseMessaging.requestPermission();
    print('FCM permissions requested'); // Debug print

    // Listen for FCM messages (optional, for push)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        showNotification(
          title: message.notification!.title ?? 'Notification',
          body: message.notification!.body ?? '',
        );
      }
    });

    // Test notification to verify service is working
    // await Future.delayed(Duration(seconds: 2));
    // await showNotification(
    //   title: 'Service Test',
    //   body: 'Notification service is active',
    // );
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    print('showNotification called: $title - $body'); // Debug print
    const androidDetails = AndroidNotificationDetails(
      'client_channel',
      'Client Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
      print('Notification sent successfully'); // Debug print
    } catch (e) {
      print('Error showing notification: $e'); // Debug print
    }
  }

  // Listen for new messages sent to the client
  void listenForNewMessages(String clientId) {
    print('Setting up message listener for clientId: $clientId'); // Debug print
    _messageListener?.cancel();

    // Use a simpler approach - listen to all messages and filter in code
    _messageListener = _firestore.collectionGroup('messages').snapshots().listen((
      snapshot,
    ) {
      print(
        'Message listener triggered with ${snapshot.docChanges.length} changes',
      ); // Debug print
      print(
        'Total documents in snapshot: ${snapshot.docs.length}',
      ); // Debug print

      for (var doc in snapshot.docChanges) {
        print('Document change type: ${doc.type}'); // Debug print
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data() as Map<String, dynamic>;
          final senderId = data['senderId'] as String?;
          final seenByClient = data['seenByClient'] as bool?;
          final senderType = data['senderType'] as String?;

          print(
            'Document data: senderId=$senderId, seenByClient=$seenByClient, clientId=$clientId, senderType=$senderType',
          ); // Debug print

          // Filter in code instead of in query
          if (senderType == 'technician' &&
              senderId != clientId &&
              seenByClient == false) {
            final text = data['text'] ?? 'Nouveau message';
            print('New message notification triggered: $text'); // Debug print
            print('Sender ID: $senderId'); // Debug print
            print('Client ID: $clientId'); // Debug print

            // Get technician name from bids collection where this technician has made bids
            _firestore
                .collection('bids')
                .where('technicianId', isEqualTo: senderId)
                .limit(1)
                .get()
                .then((bidsSnapshot) {
                  String techName = 'Technicien';
                  if (bidsSnapshot.docs.isNotEmpty) {
                    final bidData = bidsSnapshot.docs.first.data();
                    techName = bidData['technicianName'] ?? 'Technicien';
                    // Found technician name from bids
                  } else {
                    // No bids found for technician ID
                  }
                  showNotification(title: 'Message de $techName', body: text);
                })
                .catchError((error) {
                  print('Error getting technician name from bids: $error');
                  showNotification(title: 'Message de Technicien', body: text);
                });
          } else {
            // Message filtered out
          }
        }
      }
    });
  }

  // Listen for new bids on the client's requests
  void listenForNewBids(String clientId) {
    _bidListener?.cancel();
    _bidListener = _firestore
        .collection('bids')
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .listen((snapshot) {
          for (var doc in snapshot.docChanges) {
            if (doc.type == DocumentChangeType.added) {
              final data = doc.doc.data() as Map<String, dynamic>;
              final techName = data['technicianName'] ?? 'Technicien';
              final price = data['price']?.toString() ?? '';
              final createdAt = data['createdAt'] as Timestamp?;

              // Only show notification for bids created in the last 5 seconds
              // This prevents showing notifications for existing bids on app start
              if (createdAt != null) {
                final now = Timestamp.now();
                final difference = now.seconds - createdAt.seconds;
                if (difference <= 5) {
                  showNotification(
                    title: 'Nouvelle offre',
                    body: '$techName a proposé une offre de $price DT',
                  );
                } else {
                  // Bid filtered out (too old)
                }
              } else {
                // If no createdAt field, show notification (for backward compatibility)
                showNotification(
                  title: 'Nouvelle offre',
                  body: '$techName a proposé une offre de $price DT',
                );
              }
            }
          }
        });
  }

  // Listen for intervention status changes
  void listenForInterventionStatus(String clientId) {
    _interventionStatusListener?.cancel();

    // Keep track of previous status to detect changes
    Map<String, String> _previousStatuses = {};

    _interventionStatusListener = _firestore
        .collection('requests')
        .where('userId', isEqualTo: clientId)
        .snapshots()
        .listen((snapshot) {
          for (var doc in snapshot.docChanges) {
            final data = doc.doc.data() as Map<String, dynamic>;
            final interventionStatus = data['interventionStatus'] as String?;
            final requestId = doc.doc.id;

            if (interventionStatus != null) {
              final previousStatus = _previousStatuses[requestId];

              // Check if this is a new status or a status change
              if (previousStatus == null) {
                // First time seeing this request, store the status
                _previousStatuses[requestId] = interventionStatus;

                // If the initial status is 'en_cours', show notification
                if (interventionStatus == 'en_cours') {
                  _getTechnicianNameForRequest(requestId).then((techName) {
                    showNotification(
                      title: 'Technicien sur place',
                      body:
                          '$techName est arrivé sur place et commence l\'intervention',
                    );
                  });
                }
              } else if (previousStatus != interventionStatus) {
                // Status has changed

                // Update stored status
                _previousStatuses[requestId] = interventionStatus;

                // Get technician name for the notification
                _getTechnicianNameForRequest(requestId).then((techName) {
                  if (interventionStatus == 'en_cours') {
                    showNotification(
                      title: 'Technicien sur place',
                      body:
                          '$techName est arrivé sur place et commence l\'intervention',
                    );

                    // Save the intervention start time to Firebase
                    _saveInterventionStartTime(requestId);
                  } else if (interventionStatus == 'complete') {
                    showNotification(
                      title: 'Mission accomplie',
                      body: '$techName a terminé l\'intervention avec succès',
                    );
                  }
                });
              }
            }
          }
        });
  }

  // Helper method to get technician name for a request
  Future<String> _getTechnicianNameForRequest(String requestId) async {
    try {
      final bidsSnapshot = await _firestore
          .collection('bids')
          .where('requestId', isEqualTo: requestId)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      if (bidsSnapshot.docs.isNotEmpty) {
        final bidData = bidsSnapshot.docs.first.data();
        return bidData['technicianName'] ?? 'Technicien';
      }
      return 'Technicien';
    } catch (e) {
      print('Error getting technician name for request: $e');
      return 'Technicien';
    }
  }

  // Helper method to save intervention start time
  Future<void> _saveInterventionStartTime(String requestId) async {
    try {
      await _firestore.collection('requests').doc(requestId).update({
        'interventionStartTime': FieldValue.serverTimestamp(),
      });
      // Intervention start time saved
    } catch (e) {
      print('Error saving intervention start time: $e');
    }
  }

  void dispose() {
    _messageListener?.cancel();
    _bidListener?.cancel();
    _interventionStatusListener?.cancel();
    _isInitialized = false;
  }
}
