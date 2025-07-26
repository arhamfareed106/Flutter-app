import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:convert';
import 'login_client.dart';
import 'widgets/custom_app_bar.dart';

class ProfilClientPage extends StatefulWidget {
  const ProfilClientPage({super.key});

  @override
  State<ProfilClientPage> createState() => _ProfilClientPageState();
}

class _ProfilClientPageState extends State<ProfilClientPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _carBrandController = TextEditingController();
  bool _isEditing = false;
  String? _profileImageUrl;
  String? _carteGriseBase64;
  bool _isLoading = false;
  bool _isUploadingImage = false;
  final ImagePicker _picker = ImagePicker();
  XFile? _profileImage;
  XFile? _carteGriseImage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() => _isLoading = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final docRef = FirebaseFirestore.instance
          .collection('clients')
          .doc(user.uid);
      final userData = await docRef.get();

      if (userData.exists) {
        setState(() {
          _nameController.text = userData.data()?['nom'] ?? '';
          _phoneController.text = userData.data()?['telephone'] ?? '';
          _carBrandController.text = userData.data()?['marqueVehicule'] ?? '';
          _carteGriseBase64 = userData.data()?['carteGrise'] ?? '';
          _profileImageUrl = userData.data()?['profileImageUrl'] ?? '';
        });
      } else {
        // If document doesn't exist, create it with basic info
        await docRef.set({
          'nom': '',
          'telephone': '',
          'marqueVehicule': '',
          'email': user.email,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error loading user data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors du chargement du profil: ${e.toString()}',
            ),
            backgroundColor: const Color(0xFFe30713),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateProfile() async {
    try {
      setState(() => _isLoading = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      String? carteGriseBase64 = _carteGriseBase64;

      // If a new carte grise image is selected, convert it to base64
      if (_carteGriseImage != null) {
        final bytes = await _carteGriseImage!.readAsBytes();
        carteGriseBase64 = base64Encode(bytes);
      }

      // Create or update the document
      await FirebaseFirestore.instance.collection('clients').doc(user.uid).set({
        'nom': _nameController.text,
        'telephone': _phoneController.text,
        'marqueVehicule': _carBrandController.text,
        if (carteGriseBase64 != null) 'carteGrise': carteGriseBase64,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // Use merge to update existing fields

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil mis à jour avec succès'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error updating profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors de la mise à jour du profil: ${e.toString()}',
            ),
            backgroundColor: const Color(0xFFe30713),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showImagePickerOptions() async {
    if (kIsWeb) {
      _pickImage(ImageSource.gallery);
      return;
    }

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
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              if (_profileImageUrl != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Color(0xFFe30713)),
                  title: const Text(
                    'Supprimer la photo',
                    style: TextStyle(color: Color(0xFFe30713)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteProfileImage();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 500,
      );

      if (pickedFile != null) {
        setState(() => _isUploadingImage = true);
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            String fileName =
                '${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

            if (kIsWeb) {
              final bytes = await pickedFile.readAsBytes();
              final base64String =
                  'data:image/jpeg;base64,${base64Encode(bytes)}';

              await FirebaseFirestore.instance
                  .collection('clients')
                  .doc(user.uid)
                  .set({
                    'profileImageUrl': base64String,
                    'profileImageType': 'base64',
                  }, SetOptions(merge: true));

              setState(() => _profileImageUrl = base64String);
            } else {
              final file = File(pickedFile.path);
              final extension = path.extension(pickedFile.path);
              final ref = FirebaseStorage.instance.ref().child(
                'profile_images/$fileName$extension',
              );

              final uploadTask = await ref.putFile(file);
              final imageUrl = await ref.getDownloadURL();

              await FirebaseFirestore.instance
                  .collection('clients')
                  .doc(user.uid)
                  .set({
                    'profileImageUrl': imageUrl,
                    'profileImageType': 'url',
                  }, SetOptions(merge: true));

              setState(() => _profileImageUrl = imageUrl);
            }

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Photo de profil mise à jour')),
            );
          }
        } catch (e) {
          print('Error during image upload: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur lors du téléchargement de l\'image: $e'),
            ),
          );
        } finally {
          setState(() => _isUploadingImage = false);
        }
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la sélection de l\'image: $e')),
      );
    }
  }

  Future<void> _deleteProfileImage() async {
    try {
      setState(() => _isUploadingImage = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('clients')
            .doc(user.uid)
            .set({
              'profileImageUrl': null,
              'profileImageType': null,
            }, SetOptions(merge: true));

        setState(() => _profileImageUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo de profil supprimée')),
        );
      }
    } catch (e) {
      print('Error deleting profile image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la suppression de l\'image: $e'),
        ),
      );
    } finally {
      setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _pickCarteGrise() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _carteGriseImage = image;
        });
      }
    } catch (e) {
      print('Error picking carte grise: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la sélection de l\'image'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginClientPage()),
          (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la déconnexion: $e')),
      );
    }
  }

  void _showFullScreenImage(String? imageBase64) {
    if (imageBase64 == null || imageBase64.isEmpty) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.9)),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(child: Image.memory(base64Decode(imageBase64))),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
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
        final horizontalPadding = width * 0.06;
        final verticalSpacing = height * 0.025;
        final fieldSpacing = height * 0.018;
        final buttonPadding = EdgeInsets.symmetric(
          horizontal: width * 0.1,
          vertical: height * 0.018,
        );
        final fontSize = isPortrait ? 16.0 : 18.0;
        final titleFontSize = isPortrait ? 24.0 : 28.0;
        final avatarRadius = isPortrait ? width * 0.18 : width * 0.12;
        final carteGriseHeight = isPortrait ? height * 0.22 : height * 0.32;

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
                  // Profile Image Section
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _profileImage != null
                              ? (kIsWeb
                                    ? NetworkImage(_profileImage!.path)
                                    : FileImage(File(_profileImage!.path))
                                          as ImageProvider)
                              : (_profileImageUrl != null
                                    ? (_profileImageUrl!.startsWith(
                                            'data:image',
                                          )
                                          ? MemoryImage(
                                              base64Decode(
                                                _profileImageUrl!.split(',')[1],
                                              ),
                                            )
                                          : NetworkImage(_profileImageUrl!))
                                    : null),
                          child:
                              _profileImage == null && _profileImageUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFe30713),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                              ),
                              onPressed: _showImagePickerOptions,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: verticalSpacing * 1.5),
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
                  SizedBox(height: fieldSpacing),
                  // Vehicle Brand Field
                  TextField(
                    controller: _carBrandController,
                    style: TextStyle(fontSize: fontSize),
                    decoration: InputDecoration(
                      labelText: 'Marque du véhicule',
                      prefixIcon: const Icon(Icons.directions_car),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  SizedBox(height: fieldSpacing),
                  // Carte Grise Section
                  Container(
                    padding: EdgeInsets.all(width * 0.03),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Carte Grise',
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        if (_carteGriseImage != null)
                          GestureDetector(
                            onTap: () =>
                                _showFullScreenImage(_carteGriseBase64),
                            child: Container(
                              height: carteGriseHeight,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                image: DecorationImage(
                                  image: kIsWeb
                                      ? NetworkImage(_carteGriseImage!.path)
                                      : FileImage(File(_carteGriseImage!.path))
                                            as ImageProvider,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          )
                        else if (_carteGriseBase64 != null &&
                            _carteGriseBase64!.isNotEmpty)
                          GestureDetector(
                            onTap: () =>
                                _showFullScreenImage(_carteGriseBase64),
                            child: Container(
                              height: carteGriseHeight,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                image: DecorationImage(
                                  image: MemoryImage(
                                    base64Decode(_carteGriseBase64!),
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            height: carteGriseHeight,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.image,
                                size: 50,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _pickCarteGrise,
                          icon: const Icon(Icons.camera_alt),
                          label: Text(
                            _carteGriseImage == null &&
                                    (_carteGriseBase64 == null ||
                                        _carteGriseBase64!.isEmpty)
                                ? 'Scanner la carte grise'
                                : 'Changer la carte grise',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFe30713),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: height * 0.018,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: fieldSpacing),
                  // Data Protection Note
                  Container(
                    padding: EdgeInsets.all(width * 0.03),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.blue,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Vous devez scanner votre carte grise pour identifier les références de vos pièces. Vos données personnelles seront bien protégées.',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: fontSize * 0.9,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: verticalSpacing * 1.2),
                  // Update Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateProfile,
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
                              'Mettre à jour le profil',
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins',
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: fieldSpacing),
                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: Color(0xFFe30713)),
                      label: Text(
                        'Se déconnecter',
                        style: TextStyle(
                          color: const Color(0xFFe30713),
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFe30713)),
                        padding: buttonPadding,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
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

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _carBrandController.dispose();
    super.dispose();
  }
}
