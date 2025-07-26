import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'scan_carte_grise.dart';
import 'historique_client.dart';
import 'profil_client.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, listEquals;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_page.dart';
import 'services/client_notification_service.dart';

Widget phoneMailIcon({
  double phoneSize = 28,
  double mailSize = 16,
  Color color = const Color(0xFFE30713),
}) {
  return Stack(
    alignment: Alignment.center,
    children: [
      Icon(Icons.phone, size: phoneSize, color: color),
      Positioned(
        right: 0,
        top: 2,
        child: Icon(Icons.mail, size: mailSize, color: color),
      ),
    ],
  );
}

class PhoneMailWithBadge extends StatelessWidget {
  final String chatId;
  final String currentUserId;
  final String otherUserId;
  final VoidCallback? onTap;
  final double phoneSize;
  final double mailSize;

  const PhoneMailWithBadge({
    Key? key,
    required this.chatId,
    required this.currentUserId,
    required this.otherUserId,
    this.onTap,
    this.phoneSize = 20,
    this.mailSize = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isEqualTo: otherUserId)
          .where('seenByClient', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs.length ?? 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.phone, size: phoneSize, color: Color(0xFFE30713)),
                  Positioned(
                    right: 0,
                    top: 2,
                    child: Icon(
                      Icons.mail,
                      size: mailSize,
                      color: Color(0xFFE30713),
                    ),
                  ),
                ],
              ),
            ),
            if (unreadCount > 0) ...[
              SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Center(
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({super.key});

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage> {
  MapController _mapController = MapController();
  LatLng? _currentPosition;
  bool _isLoading = true;
  String? _errorMessage;
  String? _placeName;
  final TextEditingController _locationController = TextEditingController();
  String? _vehicleBrand;
  bool _hasCarteGrise = false;
  String? _carteGriseBase64;
  String _selectedProblem = 'Batterie';

  // Add controllers and state for editing
  final TextEditingController _vehicleBrandController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isEditingVehicleBrand = false;
  bool _isSaving = false;

  // New state for request management
  bool _hasActiveRequest = false;
  Map<String, dynamic>?
  _activeRequest; // Holds info like {techs: [], status: '', ...}
  List<Map<String, String>> _acceptedTechnicians = [];
  String? _pendingMessage;

  // Add a field to store technician locations for the current request
  List<LatLng> _technicianLocations = [];

  // Add a field to store OSRM durations
  List<double?> _osrmDurations = [];

  // Add a field to store accepted technician locations
  List<LatLng> _acceptedTechnicianLocations = [];

  late final StreamSubscription<User?> _authSub;

  gmaps.GoogleMapController? _googleMapController;

  double? _locationAccuracy;

  // Add state for payment mode and cheque photo
  String? _paymentMode;
  String? _chequePhotoBase64;
  bool _paymentSaved = false;

  @override
  void initState() {
    super.initState();
    print('ClientHomePage initState called'); // Debug print
    _getCurrentLocation();
    _loadUserData();
    _loadLatestRequest();

    // Check if user is already logged in
    final currentUser = FirebaseAuth.instance.currentUser;
    print('Current user in initState: ${currentUser?.uid}'); // Debug print

    if (currentUser != null) {
      _initializeNotifications();
    }

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      print('Auth state changed: ${user?.uid}'); // Debug print
      if (user != null) {
        _loadLatestRequest();
        _initializeNotifications();
      } else {
        setState(() {
          _hasActiveRequest = false;
          _activeRequest = null;
          _pendingMessage = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _locationController.dispose();
    _vehicleBrandController.dispose();
    _authSub.cancel();
    ClientNotificationService().dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userData = await FirebaseFirestore.instance
            .collection('clients')
            .doc(user.uid)
            .get();

        if (userData.exists) {
          setState(() {
            _vehicleBrand = userData.data()?['marqueVehicule'];
            _carteGriseBase64 = userData.data()?['carteGrise'];
            _hasCarteGrise = _carteGriseBase64 != null;
            _vehicleBrandController.text = _vehicleBrand ?? '';
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _initializeNotifications() async {
    print('_initializeNotifications called'); // Debug print
    try {
      final user = FirebaseAuth.instance.currentUser;
      print('Current user: ${user?.uid}'); // Debug print
      if (user != null) {
        final notificationService = ClientNotificationService();
        print('Notification service created'); // Debug print
        await notificationService.initialize();
        print('Notification service initialized'); // Debug print
        notificationService.listenForNewMessages(user.uid);
        print('Message listener set up'); // Debug print
        notificationService.listenForNewBids(user.uid);
        print('Bid listener set up'); // Debug print
        notificationService.listenForInterventionStatus(user.uid);
        print('Intervention status listener set up'); // Debug print
      } else {
        print('No user found, skipping notification setup'); // Debug print
      }
    } catch (e) {
      print('Error initializing notifications: $e');
    }
  }

  Future<bool> _handleLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // Request permission
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = kIsWeb
                ? 'Les permissions de localisation sont nécessaires. Veuillez autoriser l\'accès à la localisation dans votre navigateur et recharger la page.'
                : 'Les permissions de localisation sont nécessaires pour cette fonctionnalité.';
            _isLoading = false;
          });
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = kIsWeb
              ? 'Les permissions de localisation sont définitivement refusées. Veuillez les activer dans les paramètres de votre navigateur et recharger la page.'
              : 'Les permissions de localisation sont définitivement refusées. Veuillez les activer dans les paramètres de votre appareil.';
          _isLoading = false;
        });
        // Open app settings
        await openAppSettings();
        return false;
      }

      // For web, check if location services are enabled
      if (kIsWeb) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() {
            _errorMessage =
                'Les services de localisation sont désactivés. Veuillez les activer dans votre navigateur.';
            _isLoading = false;
          });
          return false;
        }
      }

      return true;
    } catch (e) {
      print('Error in _handleLocationPermission: $e');
      setState(() {
        _errorMessage = kIsWeb
            ? 'Une erreur est survenue lors de la vérification des permissions. Assurez-vous d\'utiliser HTTPS et d\'autoriser la localisation.'
            : 'Une erreur est survenue lors de la vérification des permissions: $e';
        _isLoading = false;
      });
      return false;
    }
  }

  Future<String> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      // Using OpenStreetMap Nominatim API (free and no API key required)
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
        ),
        headers: {'User-Agent': 'SOS Auto App'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['display_name'] != null) {
          return data['display_name'];
        }
      }
      return 'Localisation: $lat, $lng';
    } catch (e) {
      print('Error getting address: $e');
      return 'Localisation: $lat, $lng';
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final hasPermission = await _handleLocationPermission();
      if (!hasPermission) return;

      // For web, use better accuracy settings
      Position position;
      if (kIsWeb) {
        // Web-specific location settings for better accuracy
        position =
            await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.best,
              timeLimit: const Duration(seconds: 20),
              forceAndroidLocationManager:
                  false, // Use Google Play Services on Android
            ).timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                throw TimeoutException(
                  'La récupération de la position a pris trop de temps',
                );
              },
            );
      } else {
        // Mobile-specific settings
        position =
            await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 15),
            ).timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw TimeoutException(
                  'La récupération de la position a pris trop de temps',
                );
              },
            );
      }

      // Validate position
      if (position.latitude == 0 && position.longitude == 0) {
        throw Exception('Position invalide reçue');
      }

      // Additional validation for web
      if (kIsWeb) {
        // Check if position is reasonable (not too far from expected location)
        const double maxLatitude = 90.0;
        const double maxLongitude = 180.0;

        if (position.latitude.abs() > maxLatitude ||
            position.longitude.abs() > maxLongitude) {
          throw Exception('Position outside valid range');
        }

        // Check accuracy for web
        if (position.accuracy > 100000) {
          // More than 100,000 meters accuracy
          print(
            'Warning: Low accuracy location detected (${position.accuracy}m)',
          );
        }
      }

      // Get address from coordinates
      final address = await _getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _placeName = address;
        _locationController.text = address;
        _isLoading = false;
        _errorMessage = null;
        _locationAccuracy = position.accuracy; // Store accuracy for display
      });

      // Show accuracy info for web
      if (kIsWeb && position.accuracy > 100000) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'La précision de la localisation est très faible (${position.accuracy.round()}m). Essayez d\'utiliser un appareil mobile ou vérifiez les paramètres de localisation du navigateur.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      print('Error getting location: $e');
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Erreur lors de la récupération de la position: ${e.toString()}';
      });

      // Show helpful message for web users
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pour une meilleure précision sur le web, assurez-vous que votre navigateur a accès à la localisation et utilisez HTTPS.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showCarteGriseImage() {
    if (_carteGriseBase64 == null || _carteGriseBase64!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune carte grise disponible'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final imageBytes = base64Decode(_carteGriseBase64!);
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Carte Grise',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(imageBytes, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF757575), // grey[600]
                        ),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          'Mettre à jour',
                          style: TextStyle(
                            color: Color(0xFFE30713),
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le format de la carte grise est invalide.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickCarteGriseFromSource(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64 = base64Encode(bytes);
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('clients')
              .doc(user.uid)
              .set({'carteGrise': base64}, SetOptions(merge: true));
          setState(() {
            _carteGriseBase64 = base64;
            _hasCarteGrise = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Carte grise mise à jour avec succès'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Erreur lors de la sélection de l\'image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la sélection de l\'image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCarteGriseImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choisir depuis la galerie'),
                onTap: () {
                  Navigator.pop(context);
                  _pickCarteGriseFromSource(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickCarteGriseFromSource(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Call this to activate request UI (from ScanCarteGrisePage)
  void activateRequest(Map<String, dynamic> requestInfo) {
    setState(() {
      _hasActiveRequest = true;
      _activeRequest = requestInfo;
      _acceptedTechnicians = [];
      _pendingMessage = 'votre demande a été bien transmise';
    });
  }

  // Call this when a technician accepts (simulate via API/local event)
  void addAcceptedTechnician(Map<String, String> techInfo) {
    setState(() {
      _acceptedTechnicians.add(techInfo);
      _pendingMessage = null;
    });
  }

  // Cancel request logic
  void _cancelRequest() async {
    String? reason = await showDialog<String>(
      context: context,
      builder: (context) {
        String? selectedReason;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Annuler la demande'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: const Text('Attente trop longue'),
                    value: 'Attente trop longue',
                    groupValue: selectedReason,
                    onChanged: (val) => setState(() => selectedReason = val),
                  ),
                  RadioListTile<String>(
                    title: const Text('Problème résolu'),
                    value: 'Problème résolu',
                    groupValue: selectedReason,
                    onChanged: (val) => setState(() => selectedReason = val),
                  ),
                  RadioListTile<String>(
                    title: const Text('Autre'),
                    value: 'Autre',
                    groupValue: selectedReason,
                    onChanged: (val) => setState(() => selectedReason = val),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF757575), // grey[600]
                  ),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: selectedReason == null
                      ? null
                      : () => Navigator.pop(context, selectedReason),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE30713),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[400],
                    disabledForegroundColor: Colors.grey[600],
                  ),
                  child: const Text('Confirmer'),
                ),
              ],
            );
          },
        );
      },
    );
    // Update Firestore request status to 'cancelled' and all related bids
    if (_activeRequest != null && _activeRequest!['requestId'] != null) {
      final requestId = _activeRequest!['requestId'];
      // Update request status
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({'status': 'cancelled'});
      // Update all related bids
      final bidsQuery = await FirebaseFirestore.instance
          .collection('bids')
          .where('requestId', isEqualTo: requestId)
          .get();
      for (final bidDoc in bidsQuery.docs) {
        await bidDoc.reference.update({
          'status': 'cancelled_by_client',
          'cancelReason': reason,
        });
      }
    }
    setState(() {
      _hasActiveRequest = false;
      _activeRequest = null;
      _acceptedTechnicians.clear();
      _pendingMessage = null;
      _technicianLocations.clear();
      _acceptedTechnicianLocations.clear();
    });
    }

  Future<void> _loadLatestRequest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final query = await FirebaseFirestore.instance
          .collection('requests')
          .where('userId', isEqualTo: user.uid)
          .get();
      // Filter out requests without a valid createdAt timestamp
      final validDocs = query.docs.where((doc) {
        final createdAt = doc.data()['createdAt'];
        return createdAt != null && createdAt is Timestamp;
      }).toList();
      if (validDocs.isNotEmpty) {
        validDocs.sort((a, b) {
          final aTime = a.data()['createdAt'] as Timestamp;
          final bTime = b.data()['createdAt'] as Timestamp;
          return bTime.compareTo(aTime);
        });
        final data = validDocs.first.data();
        final status = data['status'] as String?;
        if (status == 'pending' || status == 'accepted') {
          setState(() {
            _hasActiveRequest = true;
            _activeRequest = {...data, 'requestId': validDocs.first.id};
            _pendingMessage = '▸▸▸▸▸▸▸▸▸▸▸▸▸▸▸';
          });
        }
      }
    } catch (e) {
      print('Error loading latest request: $e');
    }
  }

  // Function to calculate travel time and distance
  Map<String, dynamic> _calculateTravelInfo(LatLng from, LatLng to) {
    // Calculate distance using Haversine formula
    double distanceInMeters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );

    // Convert to kilometers
    double distanceInKm = distanceInMeters / 1000;

    // Estimate travel time (assuming average speed of 30 km/h in city)
    // This is a rough estimate - in a real app you'd use Google Directions API
    double estimatedTimeInMinutes = (distanceInKm / 30) * 60;

    // Use ceil to avoid 0 min for small distances
    int timeInMinutes = estimatedTimeInMinutes.ceil();

    // Show decimal for short times
    String timeDisplay;
    if (estimatedTimeInMinutes < 10 && estimatedTimeInMinutes > 0) {
      timeDisplay = estimatedTimeInMinutes.toStringAsFixed(1);
    } else {
      timeDisplay = timeInMinutes.toString();
    }

    return {'distance': distanceInKm, 'timeInMinutes': timeDisplay};
  }

  // Update fetchRouteFromOSRM to return both route and duration
  Future<Map<String, dynamic>> fetchRouteFromOSRMWithDuration(
    LatLng from,
    LatLng to,
  ) async {
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final coords = data['routes'][0]['geometry']['coordinates'] as List;
          final duration = data['routes'][0]['duration']; // in seconds
          return {
            'route': coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList(),
            'duration': duration,
          };
        }
      }
      return {'route': [], 'duration': null};
    } catch (e) {
      return {'route': [], 'duration': null};
    }
  }

  // Helper to format duration as months, weeks, days, hours, minutes (no seconds)
  String formatDurationHMS(double seconds) {
    int totalSeconds = seconds.round();
    int months = totalSeconds ~/ (30 * 24 * 3600);
    int weeks = (totalSeconds % (30 * 24 * 3600)) ~/ (7 * 24 * 3600);
    int days = (totalSeconds % (7 * 24 * 3600)) ~/ (24 * 3600);
    int hours = (totalSeconds % (24 * 3600)) ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    List<String> parts = [];
    if (months > 0) parts.add('$months mois');
    if (weeks > 0) parts.add('$weeks semaine${weeks > 1 ? 's' : ''}');
    if (days > 0) parts.add('$days jour${days > 1 ? 's' : ''}');
    if (hours > 0) parts.add('$hours heure${hours > 1 ? 's' : ''}');
    if (minutes > 0) parts.add('$minutes minute${minutes > 1 ? 's' : ''}');
    if (parts.isEmpty) parts.add('0 minute');
    return parts.join(' ');
  }

  // Helper to show payment dialog
  Future<void> _showPaymentDialog(String requestId) async {
    String? selectedMode = _paymentMode;
    String? chequePhoto = _chequePhotoBase64;
    bool isSaving = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Mode de paiement'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: const Text('Espèces'),
                    value: 'cash',
                    groupValue: selectedMode,
                    activeColor: const Color(0xFFE30713),
                    onChanged: (val) => setState(() => selectedMode = val),
                  ),
                  RadioListTile<String>(
                    title: const Text('Chèque'),
                    value: 'cheque',
                    groupValue: selectedMode,
                    activeColor: const Color(0xFFE30713),
                    onChanged: (val) => setState(() => selectedMode = val),
                  ),
                  if (selectedMode == 'cheque')
                    Column(
                      children: [
                        chequePhoto == null
                            ? ElevatedButton.icon(
                                icon: const Icon(Icons.camera_alt),
                                label: const Text(
                                  'Prendre une photo du chèque',
                                ),
                                onPressed: () async {
                                  final XFile? image = await _imagePicker
                                      .pickImage(
                                        source: ImageSource.camera,
                                        maxWidth: 800,
                                        maxHeight: 800,
                                        imageQuality: 85,
                                      );
                                  if (image != null) {
                                    final bytes = await image.readAsBytes();
                                    setState(() {
                                      chequePhoto = base64Encode(bytes);
                                    });
                                  }
                                },
                              )
                            : Column(
                                children: [
                                  Image.memory(
                                    base64Decode(chequePhoto!),
                                    height: 80,
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => chequePhoto = null),
                                    child: const Text('Changer la photo'),
                                  ),
                                ],
                              ),
                      ],
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF757575), // grey[600]
                  ),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed:
                      (selectedMode == null ||
                          (selectedMode == 'cheque' && chequePhoto == null) ||
                          isSaving)
                      ? null
                      : () async {
                          setState(() => isSaving = true);
                          // Save to Firestore
                          await FirebaseFirestore.instance
                              .collection('requests')
                              .doc(requestId)
                              .set({
                                'paymentMode': selectedMode,
                                'chequePhoto': selectedMode == 'cheque'
                                    ? chequePhoto
                                    : null,
                              }, SetOptions(merge: true));
                          setState(() {
                            _paymentMode = selectedMode;
                            _chequePhotoBase64 = chequePhoto;
                            _paymentSaved = true;
                          });
                          Navigator.pop(context);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE30713),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                  ),
                  child: const Text('Valider'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRatingDialog(String requestId) async {
    int rating = 0;
    String comment = '';
    bool isSaving = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Évaluer le service'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      5,
                      (index) => IconButton(
                        icon: Icon(
                          Icons.star,
                          color: index < rating
                              ? Color(0xFFE30713)
                              : Colors.grey[300],
                          size: 32,
                        ),
                        onPressed: () => setState(() => rating = index + 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Laisser un commentaire (optionnel)',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (val) => comment = val,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF757575), // grey[600]
                  ),
                  child: const Text('Ignorer'),
                ),
                ElevatedButton(
                  onPressed: (rating == 0 || isSaving)
                      ? null
                      : () async {
                          setState(() => isSaving = true);
                          try {
                            await FirebaseFirestore.instance
                                .collection('requests')
                                .doc(requestId)
                                .set({
                                  'clientRating': rating,
                                  'clientComment': comment,
                                }, SetOptions(merge: true));
                            Navigator.pop(context);
                          } catch (e) {
                            setState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Erreur lors de l'envoi de la note.",
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE30713),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                  ),
                  child: const Text('Envoyer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final isPortrait = mediaQuery.orientation == Orientation.portrait;
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final mapMargin = width * 0.04;
        final mapRadius = 20.0;
        final mapBoxShadow = [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];
        final buttonPadding = EdgeInsets.fromLTRB(
          width * 0.04,
          0,
          width * 0.04,
          height * 0.02,
        );
        final fieldPadding = EdgeInsets.symmetric(
          vertical: height * 0.012,
          horizontal: width * 0.04,
        );
        final buttonSpacing = height * 0.018;
        final bool hasTechnicianInfo = _technicianLocations.isNotEmpty;
        // Increase map size if client is waiting and no technician is available
        final bool isClientWaitingNoTech =
            _hasActiveRequest && _technicianLocations.isEmpty;
        final mapHeight = isClientWaitingNoTech
            ? (isPortrait
                  ? height * 0.72
                  : height * 0.82) // Slightly less than before
            : hasTechnicianInfo
            ? (isPortrait ? height * 0.66 : height * 0.78)
            : (isPortrait ? height * 0.6 : height * 0.75);
        final buttonHeight = isPortrait ? height * 0.07 : height * 0.12;
        final fontSize = width < 360 ? 14.0 : (width < 600 ? 16.0 : 18.0);
        final titleFontSize = isPortrait ? 24.0 : 28.0;

        // Widget to build the map with technician polylines
        Widget buildMapWithTechnicianPaths() {
          if (_currentPosition == null) {
            return const SizedBox();
          }

          // If there is at least one technician, fetch the OSRM route for each
          if (_technicianLocations.isNotEmpty) {
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: Future.wait(
                _technicianLocations
                    .map(
                      (techLoc) => fetchRouteFromOSRMWithDuration(
                        _currentPosition!,
                        techLoc,
                      ),
                    )
                    .toList(),
              ),
              builder: (context, snapshot) {
                List<List<LatLng>> allRoutes = [];
                List<double?> allDurations = [];
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData &&
                    snapshot.data!.isNotEmpty) {
                  allRoutes = snapshot.data!
                      .map<List<LatLng>>((m) => (m['route'] as List<LatLng>))
                      .toList();
                  allDurations = snapshot.data!
                      .map<double?>(
                        (m) => m['duration'] != null
                            ? (m['duration'] as num).toDouble()
                            : null,
                      )
                      .toList();
                }
                // Store durations for use in the UI
                _osrmDurations = allDurations;

                Set<gmaps.Marker> markers = {
                  gmaps.Marker(
                    markerId: const gmaps.MarkerId('current'),
                    position: gmaps.LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                      gmaps.BitmapDescriptor.hueRed,
                    ),
                  ),
                };
                for (int i = 0; i < _technicianLocations.length; i++) {
                  markers.add(
                    gmaps.Marker(
                      markerId: gmaps.MarkerId('tech_$i'),
                      position: gmaps.LatLng(
                        _technicianLocations[i].latitude,
                        _technicianLocations[i].longitude,
                      ),
                      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                        gmaps.BitmapDescriptor.hueBlue,
                      ),
                    ),
                  );
                }

                List<gmaps.Polyline> polylines = [];
                for (int i = 0; i < _technicianLocations.length; i++) {
                  List<LatLng> routePoints =
                      (allRoutes.length > i && allRoutes[i].isNotEmpty)
                      ? allRoutes[i]
                      : [_currentPosition!, _technicianLocations[i]];
                  bool isAccepted = _acceptedTechnicianLocations.any(
                    (loc) =>
                        loc.latitude == _technicianLocations[i].latitude &&
                        loc.longitude == _technicianLocations[i].longitude,
                  );
                  polylines.add(
                    gmaps.Polyline(
                      polylineId: gmaps.PolylineId('route_$i'),
                      points: routePoints
                          .map((p) => gmaps.LatLng(p.latitude, p.longitude))
                          .toList(),
                      color: const Color(0xFFE30713), // App red
                      width: isAccepted ? 8 : 4,
                    ),
                  );
                }

                return gmaps.GoogleMap(
                  initialCameraPosition: gmaps.CameraPosition(
                    target: gmaps.LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    zoom: 15,
                  ),
                  markers: markers,
                  polylines: Set<gmaps.Polyline>.from(polylines),
                  mapType: gmaps.MapType.normal,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  onMapCreated: (controller) {
                    _googleMapController = controller;
                  },
                );
              },
            );
          }

          // No technician locations, show just the user marker
          return gmaps.GoogleMap(
            initialCameraPosition: gmaps.CameraPosition(
              target: gmaps.LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              ),
              zoom: 15,
            ),
            markers: {
              gmaps.Marker(
                markerId: const gmaps.MarkerId('current'),
                position: gmaps.LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
                icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                  gmaps.BitmapDescriptor.hueRed,
                ),
              ),
            },
            mapType: gmaps.MapType.normal,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            onMapCreated: (controller) {
              _googleMapController = controller;
            },
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          drawer: Drawer(
            backgroundColor: Colors.white,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(color: Colors.white),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS AUTO',
                        style: TextStyle(
                          color: const Color(0xFFe30713),
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Mon Profil'),
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfilClientPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Mes Interventions'),
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HistoriqueClientPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: Stack(
              children: [
                // Main content (map and below)
                SingleChildScrollView(
                  child: Column(
                    children: [
                      // Map Container
                      SizedBox(
                        height: mapHeight,
                        child: Container(
                          margin: EdgeInsets.all(mapMargin),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(mapRadius),
                            boxShadow: mapBoxShadow,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(mapRadius),
                            child: _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFFe30713),
                                    ),
                                  )
                                : _errorMessage != null
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.error_outline,
                                          color: Color(0xFFe30713),
                                          size: 48,
                                        ),
                                        SizedBox(height: buttonSpacing),
                                        Text(
                                          _errorMessage!,
                                          style: TextStyle(
                                            color: const Color(0xFFe30713),
                                            fontFamily: 'Poppins',
                                            fontSize: fontSize,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: buttonSpacing),
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _isLoading = true;
                                              _errorMessage = null;
                                            });
                                            _getCurrentLocation();
                                          },
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Réessayer'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFe30713,
                                            ),
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: width * 0.06,
                                              vertical: height * 0.018,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : _currentPosition == null
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.location_off,
                                          color: Color(0xFFe30713),
                                          size: 48,
                                        ),
                                        SizedBox(height: buttonSpacing),
                                        Text(
                                          "Impossible d'accéder à la position",
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: fontSize,
                                            color: const Color(0xFFe30713),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : buildMapWithTechnicianPaths(),
                          ),
                        ),
                      ),

                      // UI under the map
                      _hasActiveRequest
                          ? _buildActiveRequestUI(
                              width,
                              height,
                              fontSize,
                              buttonSpacing,
                              buttonHeight,
                            )
                          : _buildDefaultRequestUI(
                              width,
                              height,
                              fontSize,
                              buttonSpacing,
                              buttonHeight,
                            ),
                    ],
                  ),
                ),
                // Menu button at top left
                Positioned(
                  top: 10,
                  left: 10,
                  child: Builder(
                    builder: (context) => Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.menu, color: Color(0xFFe30713)),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                      ),
                    ),
                  ),
                ),
                // Logo at top right
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: 40,
                        width: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDefaultRequestUI(
    double width,
    double height,
    double fontSize,
    double buttonSpacing,
    double buttonHeight,
  ) {
    return SingleChildScrollView(
      child: Container(
        padding: EdgeInsets.fromLTRB(
          width * 0.04,
          0,
          width * 0.04,
          height * 0.02,
        ),
        child: Column(
          children: [
            // Location Text Field
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.grey[300]!, width: 2),
              ),
              child: TextField(
                controller: _locationController,
                style: TextStyle(fontFamily: 'Poppins', fontSize: fontSize),
                onChanged: (value) {
                  setState(() {
                    _placeName = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: "Entrez votre localisation",
                  hintStyle: TextStyle(
                    color: Colors.grey[400],
                    fontFamily: 'Poppins',
                    fontSize: fontSize,
                  ),
                  prefixIcon: const Icon(
                    Icons.location_on,
                    color: Color(0xFFe30713),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: width * 0.04,
                    vertical: height * 0.018,
                  ),
                ),
              ),
            ),
            SizedBox(height: buttonSpacing),
            // Batterie/Pneu Dropdown and Carte Grise Button in a Row
            Row(
              children: [
                // Dropdown
                Expanded(
                  child: Container(
                    height: buttonHeight,
                    padding: EdgeInsets.symmetric(horizontal: width * 0.02),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.grey[300]!, width: 2),
                    ),
                    child: Center(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedProblem,
                          isExpanded: true,
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Color(0xFFe30713),
                          ),
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                            color: Colors.black54,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Batterie',
                              child: Center(child: Text('Batterie')),
                            ),
                            DropdownMenuItem(
                              value: 'Pneu',
                              child: Center(child: Text('Pneu')),
                            ),
                          ],
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedProblem = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: width * 0.03),
                // Carte Grise Button
                Expanded(
                  child: SizedBox(
                    height: buttonHeight,
                    child: OutlinedButton.icon(
                      icon: Icon(
                        _hasCarteGrise ? Icons.check_circle : Icons.description,
                        color: _hasCarteGrise
                            ? const Color(0xFFe30713)
                            : Colors.black,
                      ),
                      label: Text(
                        "Carte grise",
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                          color: Colors.black,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.grey[300]!, width: 2),
                        padding: EdgeInsets.symmetric(vertical: height * 0.018),
                        minimumSize: Size(double.infinity, buttonHeight),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () async {
                        if (_carteGriseBase64 != null &&
                            _carteGriseBase64!.isNotEmpty) {
                          // Show carte grise with edit option
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (context) {
                              final imageBytes = base64Decode(
                                _carteGriseBase64!,
                              );
                              return Dialog(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 16),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        imageBytes,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text(
                                            'Fermer',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text(
                                            'Mettre à jour',
                                            style: TextStyle(
                                              color: Color(0xFFE30713),
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                          if (result == true) {
                            // Pick new image
                            _showCarteGriseImageSourcePicker();
                          }
                        } else {
                          // Pick and upload new carte grise
                          _showCarteGriseImageSourcePicker();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: buttonSpacing),
            // Marque du véhicule (Editable)
            _isEditingVehicleBrand
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _vehicleBrandController,
                          decoration: InputDecoration(
                            hintText: "Marque du véhicule",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(
                                color: Colors.black,
                                width: 2,
                              ),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: width * 0.04,
                              vertical: height * 0.018,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.check, color: Color(0xFFe30713)),
                        onPressed: _isSaving
                            ? null
                            : () async {
                                setState(() {
                                  _isSaving = true;
                                });
                                final user = FirebaseAuth.instance.currentUser;
                                if (user != null) {
                                  await FirebaseFirestore.instance
                                      .collection('clients')
                                      .doc(user.uid)
                                      .update({
                                        'marqueVehicule':
                                            _vehicleBrandController.text,
                                      });
                                  setState(() {
                                    _vehicleBrand =
                                        _vehicleBrandController.text;
                                    _isEditingVehicleBrand = false;
                                  });
                                }
                                setState(() {
                                  _isSaving = false;
                                });
                              },
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _isEditingVehicleBrand = false;
                            _vehicleBrandController.text = _vehicleBrand ?? '';
                          });
                        },
                      ),
                    ],
                  )
                : GestureDetector(
                    onTap: () {
                      setState(() {
                        _isEditingVehicleBrand = true;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        vertical: height * 0.018,
                        horizontal: width * 0.04,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.grey[300]!, width: 2),
                      ),
                      child: Text(
                        _vehicleBrand ?? "Marque du véhicule",
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
            SizedBox(height: buttonSpacing),
            // Dépannage Button
            SizedBox(
              width: double.infinity,
              height: buttonHeight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bolt),
                label: Text(
                  "Demander un dépannage",
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFe30713),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: height * 0.018),
                  minimumSize: Size(double.infinity, buttonHeight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 4,
                  shadowColor: const Color(0xFFe30713).withOpacity(0.3),
                ),
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ScanCarteGrisePage(
                        initialLocation: _placeName,
                        initialPosition: _currentPosition,
                      ),
                    ),
                  );
                  if (result != null && mounted) {
                    activateRequest(result as Map<String, dynamic>);
                  }
                },
              ),
            ),
            SizedBox(height: buttonSpacing),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRequestUI(
    double width,
    double height,
    double fontSize,
    double buttonSpacing,
    double buttonHeight,
  ) {
    final String? requestId = _activeRequest?['requestId'];
    if (requestId == null) {
      return _buildDefaultRequestUI(
        width,
        height,
        fontSize,
        buttonSpacing,
        buttonHeight,
      );
    }
    // Listen to the request document in real time
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .snapshots(),
      builder: (context, requestSnapshot) {
        if (!requestSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requestData =
            requestSnapshot.data!.data() as Map<String, dynamic>?;
        if (requestData == null) {
          return _buildDefaultRequestUI(
            width,
            height,
            fontSize,
            buttonSpacing,
            buttonHeight,
          );
        }
        // If interventionStatus is complete, show default request UI
        if (requestData['interventionStatus'] == 'complete') {
          // Only show the dialog if clientRating is not set
          if (requestData['clientRating'] == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await _showRatingDialog(requestId);
              // No need to setState here, UI will update on Firestore change
            });
          }
          return _buildDefaultRequestUI(
            width,
            height,
            fontSize,
            buttonSpacing,
            buttonHeight,
          );
        }
        // Pass the real-time interventionStatus to the rest of the UI
        return _buildActiveRequestUIWithStatus(
          width,
          height,
          fontSize,
          buttonSpacing,
          buttonHeight,
          requestData['interventionStatus'] as String?,
          requestData['paymentMode'],
        );
      },
    );
  }

  // Helper to build the active request UI with real-time interventionStatus
  Widget _buildActiveRequestUIWithStatus(
    double width,
    double height,
    double fontSize,
    double buttonSpacing,
    double buttonHeight,
    String? interventionStatus,
    dynamic paymentMode, // can be String or null
  ) {
    final String? requestId = _activeRequest?['requestId'];
    final horizontalPadding = width * 0.04;
    final verticalSpacing = height * 0.025;
    final cardPadding = EdgeInsets.all(width * 0.04);
    final priceFontSize = fontSize + 2;
    // Find the first accepted technician (if any)
    String? technicianName;
    LatLng? technicianLocation;
    if (_technicianLocations.isNotEmpty) {
      technicianLocation = _technicianLocations.first;
    }
    // Try to get the technician name from the first accepted bid
    // (We will update this in the StreamBuilder below as well)
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 0, // Remove vertical padding
        ),
        child: Container(
          constraints: BoxConstraints(maxWidth: width - 2 * horizontalPadding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 0, // Remove vertical padding
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // --- NEW: Technician Action Row ---
                // Removed 'Localisation' and 'En cours de traitement' row
                // --- Technician Name Indicator (replaces request button) ---
                if (requestId != null)
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('bids')
                        .where('requestId', isEqualTo: requestId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      // Update _technicianLocations here
                      List<LatLng> newTechnicianLocations = [];
                      List<LatLng> newAcceptedTechnicianLocations = [];
                      if (snapshot.hasData) {
                        final docs = snapshot.data!.docs;
                        for (final doc in docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final loc = data['technicianLocation'];
                          if (loc != null && loc is GeoPoint) {
                            final latLng = LatLng(loc.latitude, loc.longitude);
                            newTechnicianLocations.add(latLng);
                            if (data['status'] == 'accepted') {
                              newAcceptedTechnicianLocations.add(latLng);
                            }
                          }
                        }
                        // Debug print
                        print(
                          'All technician locations for trajectory: '
                          '${newTechnicianLocations.map((e) => '(${e.latitude},${e.longitude})').join(', ')}',
                        );
                      }
                      // Update the technician locations and trigger map rebuild
                      if (!listEquals(
                            _technicianLocations,
                            newTechnicianLocations,
                          ) ||
                          !listEquals(
                            _acceptedTechnicianLocations,
                            newAcceptedTechnicianLocations,
                          )) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          setState(() {
                            _technicianLocations = newTechnicianLocations;
                            _acceptedTechnicianLocations =
                                newAcceptedTechnicianLocations;
                          });
                        });
                      }

                      if (snapshot.hasError) {
                        return Text('Erreur: ${snapshot.error}');
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return SizedBox(
                          height: buttonHeight * 1.2,
                          child: Stack(
                            children: [
                              // Animated car icon
                              _AnimatedCarWithPointer(width: width),
                            ],
                          ),
                        );
                      }

                      // Find the accepted technician name if any
                      String? techName;
                      if (snapshot.hasData) {
                        final docs = snapshot.data!.docs;
                        final acceptedDocs = docs
                            .where(
                              (doc) =>
                                  (doc.data()
                                      as Map<String, dynamic>)['status'] ==
                                  'accepted',
                            )
                            .toList();
                        QueryDocumentSnapshot? techDoc;
                        if (acceptedDocs.isNotEmpty) {
                          techDoc = acceptedDocs.first;
                        } else if (docs.isNotEmpty) {
                          techDoc = docs.first;
                        } else {
                          techDoc = null;
                        }
                        if (techDoc != null) {
                          final data = techDoc.data() as Map<String, dynamic>;
                          techName = data['technicianName'] as String?;
                        }
                      }

                      return Column(
                        children: [
                          SizedBox(height: buttonSpacing),
                          // Technician Cards
                          ListView.builder(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              final doc = snapshot.data!.docs[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final status = data['status'] as String? ?? '';
                              final user = FirebaseAuth.instance.currentUser;
                              final clientId = user?.uid ?? '';
                              Color statusColor;
                              String statusText;
                              switch (status) {
                                case 'pending':
                                  statusColor = Colors.orange;
                                  statusText = 'En attente';
                                  break;
                                case 'accepted':
                                  statusColor = Colors.green;
                                  statusText = 'Accepté';
                                  break;
                                case 'rejected':
                                  statusColor = Color(0xFFe30713);
                                  statusText = 'Rejeté';
                                  break;
                                default:
                                  statusColor = Colors.grey;
                                  statusText = status;
                              }

                              return Card(
                                color: Colors.white,
                                margin: EdgeInsets.only(
                                  bottom: verticalSpacing,
                                ),
                                child: Padding(
                                  padding: cardPadding,
                                  child: Column(
                                    children: [
                                      // Name and Phone side by side
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                vertical: height * 0.015,
                                                horizontal: width * 0.05,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                                border: Border.all(
                                                  color: Colors.grey[300]!,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Center(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.build,
                                                      color: Color(0xFFE30713),
                                                      size: fontSize + 4,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      data['technicianName'] ??
                                                          'Nom non spécifié',
                                                      style: TextStyle(
                                                        fontSize: fontSize - 2,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontFamily: 'Poppins',
                                                        color: Colors.black,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) {
                                                    return AlertDialog(
                                                      title: Text(
                                                        'Options',
                                                        style: TextStyle(
                                                          fontFamily: 'Poppins',
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          ListTile(
                                                            leading: Icon(
                                                              Icons.phone,
                                                              color: Color(
                                                                0xFFE30713,
                                                              ),
                                                            ),
                                                            title: Text(
                                                              'Appeler via votre téléphone',
                                                              style: TextStyle(
                                                                fontFamily:
                                                                    'Poppins',
                                                              ),
                                                            ),
                                                            onTap: () async {
                                                              Navigator.pop(
                                                                context,
                                                              );
                                                              final phone =
                                                                  data['technicianPhone'] ??
                                                                  '';
                                                              if (phone
                                                                  .isEmpty) {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                      'Numéro de téléphone non disponible.',
                                                                      style: TextStyle(
                                                                        fontFamily:
                                                                            'Poppins',
                                                                      ),
                                                                    ),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                  ),
                                                                );
                                                                return;
                                                              }
                                                              final telUrl =
                                                                  'tel:$phone';
                                                              final uri =
                                                                  Uri.parse(
                                                                    telUrl,
                                                                  );
                                                              if (await canLaunchUrl(
                                                                uri,
                                                              )) {
                                                                await launchUrl(
                                                                  uri,
                                                                  mode: LaunchMode
                                                                      .externalApplication,
                                                                );
                                                              } else {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                      'Impossible d\'ouvrir le composeur téléphonique.',
                                                                      style: TextStyle(
                                                                        fontFamily:
                                                                            'Poppins',
                                                                      ),
                                                                    ),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                  ),
                                                                );
                                                              }
                                                            },
                                                          ),
                                                          ListTile(
                                                            leading: Icon(
                                                              Icons.message,
                                                              color: Color(
                                                                0xFFE30713,
                                                              ),
                                                            ),
                                                            title: Text(
                                                              'Envoyer un message',
                                                              style: TextStyle(
                                                                fontFamily:
                                                                    'Poppins',
                                                              ),
                                                            ),
                                                            onTap: () {
                                                              Navigator.pop(
                                                                context,
                                                              );
                                                              final user =
                                                                  FirebaseAuth
                                                                      .instance
                                                                      .currentUser;
                                                              if (user ==
                                                                  null) {
                                                                ScaffoldMessenger.of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                      'Utilisateur non connecté.',
                                                                      style: TextStyle(
                                                                        fontFamily:
                                                                            'Poppins',
                                                                      ),
                                                                    ),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                  ),
                                                                );
                                                                return;
                                                              }
                                                              final clientId =
                                                                  user.uid;
                                                              final technicianId =
                                                                  data['technicianId'] ??
                                                                  doc.id;
                                                              final technicianName =
                                                                  data['technicianName'] ??
                                                                  '';
                                                              Navigator.push(
                                                                context,
                                                                MaterialPageRoute(
                                                                  builder: (context) => ChatPage(
                                                                    technicianId:
                                                                        technicianId,
                                                                    technicianName:
                                                                        technicianName,
                                                                    clientId:
                                                                        clientId,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                              ),
                                                          child: Text(
                                                            'Fermer',
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  'Poppins',
                                                              color: Colors
                                                                  .grey[600],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                );
                                              },
                                              child: Container(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: height * 0.015,
                                                  horizontal: width * 0.05,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(30),
                                                  border: Border.all(
                                                    color: Colors.grey[300]!,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    PhoneMailWithBadge(
                                                      chatId: _getChatId(
                                                        FirebaseAuth
                                                                .instance
                                                                .currentUser
                                                                ?.uid ??
                                                            '',
                                                        data['technicianId'] ??
                                                            doc.id,
                                                      ),
                                                      currentUserId:
                                                          FirebaseAuth
                                                              .instance
                                                              .currentUser
                                                              ?.uid ??
                                                          '',
                                                      otherUserId:
                                                          data['technicianId'] ??
                                                          doc.id,
                                                      onTap: () {
                                                        showDialog(
                                                          context: context,
                                                          builder: (context) {
                                                            return AlertDialog(
                                                              title: Text(
                                                                'Options',
                                                                style: TextStyle(
                                                                  fontFamily:
                                                                      'Poppins',
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                              ),
                                                              content: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  ListTile(
                                                                    leading: Icon(
                                                                      Icons
                                                                          .phone,
                                                                      color: Color(
                                                                        0xFFE30713,
                                                                      ),
                                                                    ),
                                                                    title: Text(
                                                                      'Appeler via votre téléphone',
                                                                      style: TextStyle(
                                                                        fontFamily:
                                                                            'Poppins',
                                                                      ),
                                                                    ),
                                                                    onTap: () async {
                                                                      Navigator.pop(
                                                                        context,
                                                                      );
                                                                      final phone =
                                                                          data['technicianPhone'] ??
                                                                          '';
                                                                      if (phone
                                                                          .isEmpty) {
                                                                        ScaffoldMessenger.of(
                                                                          context,
                                                                        ).showSnackBar(
                                                                          SnackBar(
                                                                            content: Text(
                                                                              'Numéro de téléphone non disponible.',
                                                                              style: TextStyle(
                                                                                fontFamily: 'Poppins',
                                                                              ),
                                                                            ),
                                                                            backgroundColor:
                                                                                Colors.red,
                                                                          ),
                                                                        );
                                                                        return;
                                                                      }
                                                                      final telUrl =
                                                                          'tel:$phone';
                                                                      final uri =
                                                                          Uri.parse(
                                                                            telUrl,
                                                                          );
                                                                      if (await canLaunchUrl(
                                                                        uri,
                                                                      )) {
                                                                        await launchUrl(
                                                                          uri,
                                                                          mode:
                                                                              LaunchMode.externalApplication,
                                                                        );
                                                                      } else {
                                                                        ScaffoldMessenger.of(
                                                                          context,
                                                                        ).showSnackBar(
                                                                          SnackBar(
                                                                            content: Text(
                                                                              'Impossible d\'ouvrir le composeur téléphonique.',
                                                                              style: TextStyle(
                                                                                fontFamily: 'Poppins',
                                                                              ),
                                                                            ),
                                                                            backgroundColor:
                                                                                Colors.red,
                                                                          ),
                                                                        );
                                                                      }
                                                                    },
                                                                  ),
                                                                  ListTile(
                                                                    leading: Icon(
                                                                      Icons
                                                                          .message,
                                                                      color: Color(
                                                                        0xFFE30713,
                                                                      ),
                                                                    ),
                                                                    title: Text(
                                                                      'Envoyer un message',
                                                                      style: TextStyle(
                                                                        fontFamily:
                                                                            'Poppins',
                                                                      ),
                                                                    ),
                                                                    onTap: () {
                                                                      Navigator.pop(
                                                                        context,
                                                                      );
                                                                      final user = FirebaseAuth
                                                                          .instance
                                                                          .currentUser;
                                                                      if (user ==
                                                                          null) {
                                                                        ScaffoldMessenger.of(
                                                                          context,
                                                                        ).showSnackBar(
                                                                          SnackBar(
                                                                            content: Text(
                                                                              'Utilisateur non connecté.',
                                                                              style: TextStyle(
                                                                                fontFamily: 'Poppins',
                                                                              ),
                                                                            ),
                                                                            backgroundColor:
                                                                                Colors.red,
                                                                          ),
                                                                        );
                                                                        return;
                                                                      }
                                                                      final clientId =
                                                                          user.uid;
                                                                      final technicianId =
                                                                          data['technicianId'] ??
                                                                          doc.id;
                                                                      final technicianName =
                                                                          data['technicianName'] ??
                                                                          '';
                                                                      Navigator.push(
                                                                        context,
                                                                        MaterialPageRoute(
                                                                          builder:
                                                                              (
                                                                                context,
                                                                              ) => ChatPage(
                                                                                technicianId: technicianId,
                                                                                technicianName: technicianName,
                                                                                clientId: clientId,
                                                                              ),
                                                                        ),
                                                                      );
                                                                    },
                                                                  ),
                                                                ],
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                        context,
                                                                      ),
                                                                  child: Text(
                                                                    'Fermer',
                                                                    style: TextStyle(
                                                                      fontFamily:
                                                                          'Poppins',
                                                                      color: Colors
                                                                          .grey[600],
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        );
                                                      },
                                                    ),
                                                    SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        data['technicianPhone'] ??
                                                            'Téléphone non spécifié',
                                                        style: TextStyle(
                                                          fontSize:
                                                              fontSize - 2,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontFamily: 'Poppins',
                                                          color: Colors.black,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      // Model (car brand) and Immatriculation side by side
                                      if ((data['technicianCarBrand'] != null &&
                                              data['technicianCarBrand']
                                                  .toString()
                                                  .isNotEmpty) ||
                                          (data['technicianImmatriculation'] !=
                                                  null &&
                                              data['technicianImmatriculation']
                                                  .toString()
                                                  .isNotEmpty))
                                        Row(
                                          children: [
                                            if (data['technicianCarBrand'] !=
                                                    null &&
                                                data['technicianCarBrand']
                                                    .toString()
                                                    .isNotEmpty)
                                              Expanded(
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    vertical: height * 0.015,
                                                    horizontal: width * 0.05,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          30,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.grey[300]!,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons.directions_car,
                                                        color: Color(
                                                          0xFFE30713,
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Flexible(
                                                        child: Text(
                                                          data['technicianCarBrand'],
                                                          style: TextStyle(
                                                            fontSize:
                                                                fontSize - 2,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontFamily:
                                                                'Poppins',
                                                            color: Colors.black,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            if (data['technicianCarBrand'] !=
                                                    null &&
                                                data['technicianCarBrand']
                                                    .toString()
                                                    .isNotEmpty &&
                                                data['technicianImmatriculation'] !=
                                                    null &&
                                                data['technicianImmatriculation']
                                                    .toString()
                                                    .isNotEmpty)
                                              SizedBox(width: 8),
                                            if (data['technicianImmatriculation'] !=
                                                    null &&
                                                data['technicianImmatriculation']
                                                    .toString()
                                                    .isNotEmpty)
                                              Expanded(
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    vertical: height * 0.015,
                                                    horizontal: width * 0.05,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          30,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.grey[300]!,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .confirmation_number,
                                                        color: Color(
                                                          0xFFE30713,
                                                        ),
                                                      ),
                                                      SizedBox(width: 8),
                                                      Flexible(
                                                        child: Text(
                                                          data['technicianImmatriculation'],
                                                          style: TextStyle(
                                                            fontSize:
                                                                fontSize - 2,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontFamily:
                                                                'Poppins',
                                                            color: Colors.black,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                          // Removed overflow and maxLines
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      SizedBox(height: 8),
                                      // Price and Travel Time side by side
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              width: double.infinity,
                                              padding: EdgeInsets.symmetric(
                                                vertical: height * 0.018,
                                                horizontal: width * 0.04,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                                border: Border.all(
                                                  color: Colors.grey[300]!,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Text(
                                                'Prix:  ${data['price'] ?? 'Non spécifié'}',
                                                style: TextStyle(
                                                  fontSize: fontSize - 2,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Poppins',
                                                  color: Colors.black,
                                                ),
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Container(
                                              width: double.infinity,
                                              padding: EdgeInsets.symmetric(
                                                vertical: height * 0.018,
                                                horizontal: width * 0.04,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                                border: Border.all(
                                                  color: Colors.grey[300]!,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Builder(
                                                builder: (context) {
                                                  if (interventionStatus ==
                                                      'en_cours') {
                                                    return Container(
                                                      width: double.infinity,
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            "En cours d'intervention",
                                                            style: TextStyle(
                                                              fontSize:
                                                                  fontSize - 3,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontFamily:
                                                                  'Poppins',
                                                              color:
                                                                  Colors.black,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                            maxLines: 2,
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .timer_outlined,
                                                                color: Color(
                                                                  0xFFE30713,
                                                                ),
                                                                size: 14,
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Chronometer(
                                                                requestId:
                                                                    requestId,
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }
                                                  if (interventionStatus !=
                                                      'en_cours') {
                                                    if (_currentPosition !=
                                                        null) {
                                                      final techLocation =
                                                          data['technicianLocation'];
                                                      if (techLocation !=
                                                              null &&
                                                          techLocation
                                                              is GeoPoint) {
                                                        final travelInfo =
                                                            _calculateTravelInfo(
                                                              _currentPosition!,
                                                              LatLng(
                                                                techLocation
                                                                    .latitude,
                                                                techLocation
                                                                    .longitude,
                                                              ),
                                                            );
                                                        int
                                                        techIndex = _technicianLocations.indexWhere(
                                                          (loc) =>
                                                              loc.latitude ==
                                                                  techLocation
                                                                      .latitude &&
                                                              loc.longitude ==
                                                                  techLocation
                                                                      .longitude,
                                                        );
                                                        String timeDisplay;
                                                        if (techIndex != -1 &&
                                                            _osrmDurations
                                                                    .length >
                                                                techIndex &&
                                                            _osrmDurations[techIndex] !=
                                                                null) {
                                                          double seconds =
                                                              _osrmDurations[techIndex]!;
                                                          if (seconds <= 300) {
                                                            // Show countdown timer for <= 5 minutes
                                                            return Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .timer_outlined,
                                                                  color: Color(
                                                                    0xFFE30713,
                                                                  ),
                                                                  size: 14,
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Flexible(
                                                                  child: Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      const Icon(
                                                                        Icons
                                                                            .timer_outlined,
                                                                        color: Color(
                                                                          0xFFE30713,
                                                                        ),
                                                                        size:
                                                                            14,
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            4,
                                                                      ),
                                                                      Text(
                                                                        'Durée: ',
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              fontSize -
                                                                              2,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          fontFamily:
                                                                              'Poppins',
                                                                          color:
                                                                              Colors.black,
                                                                        ),
                                                                      ),
                                                                      CountdownTimer(
                                                                        initialSeconds:
                                                                            seconds.round(),
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              fontSize -
                                                                              2,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          fontFamily:
                                                                              'Poppins',
                                                                          color:
                                                                              Colors.black,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            );
                                                          } else {
                                                            timeDisplay =
                                                                formatDurationHMS(
                                                                  seconds,
                                                                );
                                                          }
                                                        } else {
                                                          double
                                                          fallbackSeconds =
                                                              double.tryParse(
                                                                    travelInfo['timeInMinutes']
                                                                        .toString(),
                                                                  ) !=
                                                                  null
                                                              ? double.parse(
                                                                      travelInfo['timeInMinutes']
                                                                          .toString(),
                                                                    ) *
                                                                    60
                                                              : 0;
                                                          if (fallbackSeconds <=
                                                                  300 &&
                                                              fallbackSeconds >
                                                                  0) {
                                                            return Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .timer_outlined,
                                                                  color: Color(
                                                                    0xFFE30713,
                                                                  ),
                                                                  size: 14,
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Flexible(
                                                                  child: Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      const Icon(
                                                                        Icons
                                                                            .timer_outlined,
                                                                        color: Color(
                                                                          0xFFE30713,
                                                                        ),
                                                                        size:
                                                                            14,
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            4,
                                                                      ),
                                                                      Text(
                                                                        'Durée: ',
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              fontSize -
                                                                              2,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          fontFamily:
                                                                              'Poppins',
                                                                          color:
                                                                              Colors.black,
                                                                        ),
                                                                      ),
                                                                      CountdownTimer(
                                                                        initialSeconds:
                                                                            fallbackSeconds.round(),
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              fontSize -
                                                                              2,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          fontFamily:
                                                                              'Poppins',
                                                                          color:
                                                                              Colors.black,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            );
                                                          }
                                                          timeDisplay =
                                                              formatDurationHMS(
                                                                fallbackSeconds,
                                                              );
                                                        }
                                                        return Text(
                                                          'Durée:  $timeDisplay',
                                                          style: TextStyle(
                                                            fontSize:
                                                                fontSize - 2,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontFamily:
                                                                'Poppins',
                                                            color: Colors.black,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        );
                                                      }
                                                    }
                                                  }
                                                  return Text(
                                                    'Durée:  ${data['duration'] ?? 'Non spécifié'}',
                                                    style: TextStyle(
                                                      fontSize: fontSize - 2,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontFamily: 'Poppins',
                                                      color: Colors.white,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      // Accept/Reject buttons
                                      if (status == 'pending')
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () async {
                                              try {
                                                await doc.reference.update({
                                                  'status': 'accepted',
                                                });
                                                for (final otherDoc
                                                    in snapshot.data!.docs) {
                                                  if (otherDoc.id != doc.id) {
                                                    await otherDoc.reference
                                                        .update({
                                                          'status': 'rejected',
                                                        });
                                                  }
                                                }
                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Technicien confirmé',
                                                        style: TextStyle(
                                                          fontFamily: 'Poppins',
                                                        ),
                                                      ),
                                                      backgroundColor: Color(
                                                        0xFFE30713,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Erreur: $e',
                                                        style: TextStyle(
                                                          fontFamily: 'Poppins',
                                                        ),
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Color(
                                                0xFFE30713,
                                              ),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                              padding: EdgeInsets.symmetric(
                                                vertical: height * 0.018,
                                              ),
                                            ),
                                            child: Text(
                                              'Confirmer',
                                              style: TextStyle(
                                                fontSize: fontSize - 2,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Poppins',
                                              ),
                                            ),
                                          ),
                                        ),
                                      // Add payment button if not yet saved
                                      if (status == 'accepted' &&
                                          paymentMode == null) ...[
                                        SizedBox(height: 12),
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.payment),
                                          label: const Text('Mode de paiement'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFE30713,
                                            ),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 24,
                                            ),
                                          ),
                                          onPressed: () async {
                                            final requestId =
                                                _activeRequest?['requestId'];
                                            if (requestId != null) {
                                              await _showPaymentDialog(
                                                requestId,
                                              );
                                            }
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                SizedBox(height: buttonSpacing),
                if (_technicianLocations.isEmpty)
                  Text(
                    '⌛Un dépanneur va bientôt apparaître sur la carte...',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: const Color(0xFFe30713),
                    ),
                  ),
                SizedBox(height: buttonSpacing),
                if (_technicianLocations.isEmpty)
                  SizedBox(
                    width: width * 0.5,
                    height: buttonHeight * 0.7,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text(
                        'Annuler',
                        style: TextStyle(fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30713),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: EdgeInsets.symmetric(vertical: height * 0.01),
                      ),
                      onPressed: _cancelRequest,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getChatId(String clientId, String technicianId) {
    final ids = [clientId, technicianId]..sort();
    return "${ids[0]}_${ids[1]}";
  }
}

// CountdownTimer widget for technician ETA
class CountdownTimer extends StatefulWidget {
  final int initialSeconds;
  final TextStyle? style;
  final VoidCallback? onFinished;
  const CountdownTimer({
    Key? key,
    required this.initialSeconds,
    this.style,
    this.onFinished,
  }) : super(key: key);

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.initialSeconds;
    if (_secondsLeft > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsLeft > 0) {
          setState(() {
            _secondsLeft--;
          });
          if (_secondsLeft == 0 && widget.onFinished != null) {
            widget.onFinished!();
          }
        } else {
          timer.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(int seconds) {
    if (seconds <= 0) return '0';
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '${m}min ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(_secondsLeft),
      style:
          widget.style ??
          const TextStyle(
            color: Color(0xFFE30713),
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
    );
  }
}

class _AnimatedCarWithPointer extends StatefulWidget {
  final double width;
  const _AnimatedCarWithPointer({required this.width});

  @override
  State<_AnimatedCarWithPointer> createState() =>
      _AnimatedCarWithPointerState();
}

class _AnimatedCarWithPointerState extends State<_AnimatedCarWithPointer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  static const double carIconWidth = 32;
  static const double pointerIconWidth = 32;
  static const double buffer = 16; // space between car and pointer

  @override
  void initState() {
    super.initState();
    double maxTravel = widget.width - carIconWidth - pointerIconWidth - buffer;
    if (maxTravel < 0) maxTravel = 0;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12), // slower animation duration
    );

    // Create a sequence animation: forward to pointer, pause, then reverse
    _animation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: maxTravel * 0.85,
        ), // Stop at 85% of the way
        weight: 40, // 40% of total time
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: maxTravel * 0.85,
          end: maxTravel * 0.85,
        ), // Pause
        weight: 20, // 20% of total time (pause)
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: maxTravel * 0.85,
          end: 0,
        ), // Return to start
        weight: 40, // 40% of total time
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Start the animation and repeat
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Wait a bit before repeating
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _controller.reset();
            _controller.forward();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: carIconWidth + 8,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Stack(
            children: [
              // Car icon (animated)
              Positioned(
                left: _animation.value,
                top: 0,
                child: Icon(
                  Icons.directions_car,
                  color: Color(0xFFE30713),
                  size: carIconWidth,
                ),
              ),
              // Pointer icon (fixed at right)
              Positioned(
                right: 0,
                top: 0,
                child: Icon(
                  Icons.place,
                  color: Color(0xFFE30713),
                  size: pointerIconWidth,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Add Chronometer widget for intervention
class Chronometer extends StatefulWidget {
  final String? requestId;
  const Chronometer({Key? key, this.requestId}) : super(key: key);

  @override
  State<Chronometer> createState() => _ChronometerState();
}

class _ChronometerState extends State<Chronometer> {
  Timer? _timer;
  int _seconds = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStartTimeAndStart();
  }

  Future<void> _loadStartTimeAndStart() async {
    if (widget.requestId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .get();
        final data = doc.data();
        if (data != null && data['interventionStartTime'] != null) {
          final startTime = data['interventionStartTime'] as Timestamp;
          final now = Timestamp.now();
          final elapsedSeconds = now.seconds - startTime.seconds;
          setState(() {
            _seconds = elapsedSeconds;
            _isLoading = false;
          });
          _start();
        } else {
          setState(() {
            _seconds = 0;
            _isLoading = false;
          });
          _start();
        }
      } catch (e) {
        setState(() {
          _seconds = 0;
          _isLoading = false;
        });
        _start();
      }
    } else {
      setState(() {
        _seconds = 0;
        _isLoading = false;
      });
      _start();
    }
  }

  void _start() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _seconds++;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Text('00:00:00');
    }
    return Text(
      _format(_seconds),
      style: const TextStyle(
        color: Color(0xFFE30713),
        fontWeight: FontWeight.bold,
        fontFamily: 'Poppins',
      ),
    );
  }
}
