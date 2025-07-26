import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'widgets/custom_app_bar.dart';
import 'client_home.dart';

class RegisterClientPage extends StatefulWidget {
  const RegisterClientPage({super.key});

  @override
  State<RegisterClientPage> createState() => _RegisterClientPageState();
}

class _RegisterClientPageState extends State<RegisterClientPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _carBrandController = TextEditingController();
  bool _isLoading = false;
  String? _carteGriseBase64;
  final ImagePicker _picker = ImagePicker();
  bool _isPhoneVerified = false;
  String? _verificationId;
  bool _isVerifyingPhone = false;

  Future<void> _pickCarteGrise() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _carteGriseBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de la capture de l\'image'),
          backgroundColor: Color(0xFFe30713),
        ),
      );
    }
  }

  Future<void> _registerClient() async {
    if (_carteGriseBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez scanner votre carte grise'),
          backgroundColor: Color(0xFFe30713),
        ),
      );
      return;
    }

    if (_phoneController.text.isEmpty || _carBrandController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez remplir tous les champs requis'),
          backgroundColor: Color(0xFFe30713),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      // Save user data to Firestore
      await FirebaseFirestore.instance
          .collection('clients')
          .doc(userCredential.user!.uid)
          .set({
            'nom': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'telephone': _phoneController.text.trim(),
            'marqueVehicule': _carBrandController.text.trim(),
            'carteGrise': _carteGriseBase64,
            'createdAt': Timestamp.now(),
          });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ClientHomePage()),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Erreur lors de l\'inscription';
      if (e.code == 'email-already-in-use') {
        message = 'Cet email est déjà utilisé.';
      } else if (e.code == 'weak-password') {
        message = 'Mot de passe trop faible.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showSmsCodeDialog() async {
    final codeController = TextEditingController();
    String? errorText;
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Vérification SMS'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Entrez le code reçu par SMS'),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Code SMS',
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setState(() => errorText = null);
                    try {
                      final credential = PhoneAuthProvider.credential(
                        verificationId: _verificationId!,
                        smsCode: codeController.text.trim(),
                      );
                      await FirebaseAuth.instance.signInWithCredential(
                        credential,
                      );
                      setState(() {
                        _isPhoneVerified = true;
                      });
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Téléphone vérifié avec succès!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } on FirebaseAuthException catch (e) {
                      setState(() => errorText = e.message ?? 'Code invalide');
                    }
                  },
                  child: const Text('Vérifier'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _verifyPhoneNumber() async {
    setState(() => _isVerifyingPhone = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _phoneController.text.trim(),
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          setState(() {
            _isPhoneVerified = true;
            _isVerifyingPhone = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Téléphone vérifié automatiquement!'),
              backgroundColor: Colors.green,
            ),
          );
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isVerifyingPhone = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message ?? 'Erreur de vérification'),
              backgroundColor: Colors.red,
            ),
          );
        },
        codeSent: (String verificationId, int? resendToken) async {
          setState(() {
            _verificationId = verificationId;
            _isVerifyingPhone = false;
          });
          await _showSmsCodeDialog();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() {
            _verificationId = verificationId;
            _isVerifyingPhone = false;
          });
        },
      );
      return _isPhoneVerified;
    } catch (e) {
      setState(() => _isVerifyingPhone = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  Future<void> _onRegisterPressed() async {
    if (!_isPhoneVerified) {
      if (_phoneController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Veuillez entrer votre numéro de téléphone'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_isVerifyingPhone) return;
      final verified = await _verifyPhoneNumber();
      if (!verified) return;
    }
    await _registerClient();
  }

  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFe30713);
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final isPortrait = mediaQuery.orientation == Orientation.portrait;
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final horizontalPadding = width * 0.06;
        final logoHeight = isPortrait ? height * 0.18 : height * 0.28;
        final verticalSpacing = height * 0.025;
        final fieldSpacing = height * 0.018;
        final buttonPadding = EdgeInsets.symmetric(
          horizontal: width * 0.1,
          vertical: height * 0.018,
        );
        final fontSize = isPortrait ? 16.0 : 18.0;
        final titleFontSize = isPortrait ? 24.0 : 28.0;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: const CustomAppBar(title: '', showImage: false),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalSpacing,
              ),
              child: Column(
                children: [
                  SizedBox(height: verticalSpacing),
                  Image.asset('assets/images/logo.png', height: logoHeight),
                  SizedBox(height: verticalSpacing * 1.5),
                  Text(
                    'Inscription Client',
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  SizedBox(height: verticalSpacing * 1.5),
                  // Nom
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
                  // Email
                  TextField(
                    controller: _emailController,
                    style: TextStyle(fontSize: fontSize),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  SizedBox(height: fieldSpacing),
                  // Mot de passe
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: TextStyle(fontSize: fontSize),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                  SizedBox(height: fieldSpacing),
                  // Numéro de téléphone
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
                  // Marque du véhicule
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
                  // Carte grise scan
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.document_scanner),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Scannez votre carte grise',
                              style: TextStyle(fontSize: fontSize),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '*',
                            style: TextStyle(
                              color: Color(0xFFe30713),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      trailing: _carteGriseBase64 != null
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.camera_alt),
                      onTap: _pickCarteGrise,
                    ),
                  ),
                  SizedBox(height: fieldSpacing),
                  Container(
                    padding: EdgeInsets.all(width * 0.03),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.blue,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Vous devez scannez votre carte grise pour identifier les références de vos pièces. Vos données personnelles seront bien protégées.',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: fontSize * 0.95,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: verticalSpacing * 1.5),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading || _isVerifyingPhone
                          ? null
                          : _onRegisterPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: redColor,
                        foregroundColor: Colors.white,
                        padding: buttonPadding,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: (_isLoading || _isVerifyingPhone)
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              'Créer le compte',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: fontSize,
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
