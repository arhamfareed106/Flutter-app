import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'widgets/custom_app_bar.dart';

class ScanCarteGrisePage extends StatefulWidget {
  final String? initialLocation;
  final LatLng? initialPosition;

  const ScanCarteGrisePage({
    super.key,
    this.initialLocation,
    this.initialPosition,
  });

  @override
  State<ScanCarteGrisePage> createState() => _ScanCarteGrisePageState();
}

class _ScanCarteGrisePageState extends State<ScanCarteGrisePage> {
  bool _isLoading = false;
  LatLng? _currentPosition;
  String? _placeName;
  final ImagePicker _picker = ImagePicker();

  // Add controllers for new fields
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _schedulingOption = 'maintenant';
  XFile? _problemImage;
  String? _problemImageBase64;
  String? _selectedHour;
  DateTime? _selectedDateTime;
  final List<String> _hours = List.generate(
    12,
    (i) => '${i + 1} heure${i == 0 ? '' : 's'}',
  );

  // Add carte grise field
  String? _carteGriseBase64;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    if (widget.initialLocation != null && widget.initialPosition != null) {
      setState(() {
        _placeName = widget.initialLocation;
        _currentPosition = widget.initialPosition;
      });
    } else {
      _getCurrentLocation(); // Only get location if not provided
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Les services de localisation sont désactivés. Veuillez les activer.',
          ),
          backgroundColor: Color(0xFFe30713),
        ),
      );
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Les permissions de localisation sont refusées'),
            backgroundColor: Color(0xFFe30713),
          ),
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Les permissions de localisation sont définitivement refusées. Veuillez les activer dans les paramètres.',
          ),
          backgroundColor: Color(0xFFe30713),
        ),
      );
      return false;
    }
    return true;
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
      return 'Location: $lat, $lng';
    } catch (e) {
      print('Error getting address: $e');
      return 'Location: $lat, $lng';
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check location permission first
      final hasPermission = await _handleLocationPermission();
      if (!hasPermission) return;

      // Get current position with high accuracy
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      // Validate position
      if (position.latitude == 0 && position.longitude == 0) {
        throw Exception('Invalid position received');
      }

      // Check if position is reasonable (not too far from expected location)
      // You can adjust these values based on your expected location
      const double maxLatitude = 90.0;
      const double maxLongitude = 180.0;

      if (position.latitude.abs() > maxLatitude ||
          position.longitude.abs() > maxLongitude) {
        throw Exception('Position outside valid range');
      }

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      // Get address asynchronously
      final address = await _getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _placeName = address;
      });
    } catch (e) {
      print('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erreur lors de la récupération de la position: ${e.toString()}',
          ),
          backgroundColor: Color(0xFFe30713),
        ),
      );
    }
  }

  Future<void> _pickProblemImageFromSource(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _problemImage = image;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de la sélection de l\'image'),
          backgroundColor: Color(0xFFe30713),
        ),
      );
    }
  }

  void _showProblemImageSourcePicker() {
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
                  _pickProblemImageFromSource(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickProblemImageFromSource(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _getProblemImageBase64() async {
    if (_problemImage == null) return '';

    try {
      final bytes = await _problemImage!.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      throw Exception('Erreur lors de la conversion de l\'image en base64');
    }
  }

  Future<void> _markOldRequestsInactive(String userId) async {
    final query = await FirebaseFirestore.instance
        .collection('requests')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'accepted'])
        .get();
    for (final doc in query.docs) {
      await doc.reference.update({'status': 'cancelled'});
    }
  }

  Future<void> _uploadDocument() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En attente de la localisation...'),
          backgroundColor: Color(0xFFe30713),
        ),
      );
      return;
    }

    if (_schedulingOption == 'programmer' && _selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veuillez sélectionner la date et l\'heure pour l\'intervention',
          ),
          backgroundColor: Color(0xFFe30713),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Utilisateur non connecté');
      }

      // Fetch car brand from client profile
      String carBrand = '';
      final userData = await FirebaseFirestore.instance
          .collection('clients')
          .doc(user.uid)
          .get();
      if (userData.exists) {
        carBrand = userData.data()?['marqueVehicule'] ?? '';
      }

      // Mark old requests as inactive
      await _markOldRequestsInactive(user.uid);

      // Get problem image base64 if exists
      String problemImageBase64 = '';
      if (_problemImage != null) {
        problemImageBase64 = await _getProblemImageBase64();
      }

      // Create the request document
      final docRef = await FirebaseFirestore.instance
          .collection('requests')
          .add({
            'userId': user.uid,
            'name': _nameController.text,
            'phone': _phoneController.text,
            'description': _descriptionController.text,
            'problemImage': problemImageBase64,
            'carteGrise': _carteGriseBase64,
            'carBrand': carBrand, // <-- Add car brand here
            'location': GeoPoint(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            'placeName': _placeName,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'schedulingOption': _schedulingOption,
            if (_schedulingOption == 'programmer' && _selectedDateTime != null)
              'scheduledDateTime': Timestamp.fromDate(_selectedDateTime!),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demande envoyée avec succès'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, {
          'requestId': docRef.id,
          'name': _nameController.text,
          // Add more fields if needed
        });
      }
    } catch (e) {
      print('Error uploading document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de l\'envoi de la demande: ${e.toString()}',
            ),
            backgroundColor: Color(0xFFe30713),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      setState(() => _isLoading = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userData = await FirebaseFirestore.instance
            .collection('clients')
            .doc(user.uid)
            .get();

        if (userData.exists) {
          setState(() {
            _nameController.text = userData.data()?['nom'] ?? '';
            _phoneController.text = userData.data()?['telephone'] ?? '';
            _carteGriseBase64 = userData.data()?['carteGrise'];
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erreur lors du chargement des données: ${e.toString()}',
          ),
          backgroundColor: Color(0xFFe30713),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final isPortrait = mediaQuery.orientation == Orientation.portrait;
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final horizontalPadding = width * 0.06;
        final verticalSpacing = height * 0.025;
        final fieldSpacing = height * 0.018;
        final buttonPadding = EdgeInsets.symmetric(
          horizontal: width * 0.1,
          vertical: height * 0.018,
        );
        final fontSize = isPortrait ? 16.0 : 18.0;
        final titleFontSize = isPortrait ? 24.0 : 28.0;
        final problemImageHeight = isPortrait ? height * 0.25 : height * 0.35;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: const CustomAppBar(title: '', showBackButton: true),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalSpacing,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Name Field
                  TextField(
                    controller: _nameController,
                    style: TextStyle(fontSize: fontSize),
                    decoration: InputDecoration(
                      labelText: 'Nom complet',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  SizedBox(height: fieldSpacing),
                  // Phone Field
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(fontSize: fontSize),
                    decoration: InputDecoration(
                      labelText: 'Numéro de téléphone',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  SizedBox(height: verticalSpacing * 1.2),
                  // Type d'intervention
                  Text(
                    'Type d\'intervention',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: width * 0.03,
                      vertical: height * 0.008,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _schedulingOption,
                        isExpanded: true,
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Color(0xFFe30713),
                        ),
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: fontSize,
                          fontFamily: 'Poppins',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'maintenant',
                            child: Text('Demander maintenant'),
                          ),
                          DropdownMenuItem(
                            value: 'programmer',
                            child: Text('Programmer l\'intervention'),
                          ),
                        ],
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _schedulingOption = newValue;
                              if (newValue == 'maintenant') {
                                _selectedHour = null;
                                _selectedDateTime = null;
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  if (_schedulingOption == 'programmer') ...[
                    SizedBox(height: fieldSpacing),
                    Text(
                      'Date et heure de l\'intervention',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.calendar_month,
                          color: Color(0xFFe30713),
                        ),
                        label: Text(
                          _selectedDateTime == null
                              ? 'Choisir la date et l\'heure'
                              : '${_selectedDateTime!.day.toString().padLeft(2, '0')}/'
                                    '${_selectedDateTime!.month.toString().padLeft(2, '0')}/'
                                    '${_selectedDateTime!.year} '
                                    'à '
                                    '${_selectedDateTime!.hour.toString().padLeft(2, '0')}:'
                                    '${_selectedDateTime!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.black,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                            fontSize: fontSize,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Colors.black, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () async {
                          DateTime now = DateTime.now();
                          DateTime? pickedDate = await showDatePicker(
                            context: context,
                            initialDate: now,
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 365)),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: Color(0xFFe30713),
                                    onPrimary: Colors.white,
                                    onSurface: Colors.black,
                                  ),
                                  textButtonTheme: TextButtonThemeData(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Color(0xFFe30713),
                                    ),
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          TimeOfDay? pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: Color(0xFFE30713),
                                    onPrimary: Colors.white,
                                    onSurface: Colors.black,
                                  ),
                                  timePickerTheme: TimePickerThemeData(
                                    dialHandColor: Color(0xFFE30713),
                                    hourMinuteTextColor: Colors.black,
                                    dayPeriodColor: Color(0xFFE30713),
                                    dayPeriodTextColor: Colors.black,
                                    entryModeIconColor: Color(0xFFE30713),
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (pickedDate != null && pickedTime != null) {
                            setState(() {
                              _selectedDateTime = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                            });
                          }
                                                },
                      ),
                    ),
                  ],
                  SizedBox(height: fieldSpacing),
                  // Description Field
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    style: TextStyle(fontSize: fontSize),
                    decoration: InputDecoration(
                      labelText: 'Description du problème',
                      hintText: 'Décrivez le problème en détail',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignLabelWithHint: true,
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  SizedBox(height: fieldSpacing),
                  // Problem Photo Section
                  Text(
                    'Photo du problème',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    height: problemImageHeight,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _problemImage != null
                        ? Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: kIsWeb
                                    ? Image.network(
                                        _problemImage!.path,
                                        width: double.infinity,
                                        height: problemImageHeight,
                                        fit: BoxFit.cover,
                                      )
                                    : Image.file(
                                        File(_problemImage!.path),
                                        width: double.infinity,
                                        height: problemImageHeight,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _problemImage = null;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_a_photo,
                                    size: 40,
                                    color: Color(0xFFe30713),
                                  ),
                                  onPressed: _showProblemImageSourcePicker,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ajouter une photo du problème',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontFamily: 'Poppins',
                                    fontSize: fontSize * 0.95,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  SizedBox(height: fieldSpacing),
                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _uploadDocument,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFe30713),
                        foregroundColor: Colors.white,
                        padding: buttonPadding,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              'Confirmer la demande',
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
