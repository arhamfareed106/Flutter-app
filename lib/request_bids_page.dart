import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'widgets/custom_app_bar.dart';

class RequestBidsPage extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> requestData;

  const RequestBidsPage({
    super.key,
    required this.requestId,
    required this.requestData,
  });

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'En attente';
      case 'accepted':
        return 'Accepté';
      case 'rejected':
        return 'Rejeté';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Color(0xFFe30713);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Utilisateur non connecté')),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final isPortrait = mediaQuery.orientation == Orientation.portrait;
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final horizontalPadding = width * 0.06;
        final verticalSpacing = height * 0.025;
        final cardPadding = EdgeInsets.all(width * 0.04);
        final cardMargin = EdgeInsets.all(width * 0.04);
        final fontSize = isPortrait ? 16.0 : 18.0;
        final titleFontSize = isPortrait ? 18.0 : 22.0;
        final priceFontSize = isPortrait ? 18.0 : 22.0;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: const CustomAppBar(
            title: '',
            showBackButton: true,
            showImage: true,
          ),
          body: Column(
            children: [
              // Request Details Card
              Card(
                margin: cardMargin,
                child: Padding(
                  padding: cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Détails de la demande',
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      SizedBox(height: verticalSpacing * 0.5),
                      Text(
                        'Marque du véhicule: ${requestData['carBrand']}',
                        style: TextStyle(fontSize: fontSize),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Description: ${requestData['description']}',
                        style: TextStyle(fontSize: fontSize),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Adresse: ${requestData['placeName']}',
                        style: TextStyle(fontSize: fontSize),
                      ),
                    ],
                  ),
                ),
              ),

              // Bids List
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('bids')
                      .where('requestId', isEqualTo: requestId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Erreur: ${snapshot.error}'));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Chargement des offres...'),
                            SizedBox(height: 16),
                            CircularProgressIndicator(),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'Aucune offre disponible',
                          style: TextStyle(fontSize: 16, fontFamily: 'Poppins'),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalSpacing,
                      ),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final doc = snapshot.data!.docs[index];
                        final data = doc.data() as Map<String, dynamic>;

                        // Format the date
                        final Timestamp? timestamp =
                            data['createdAt'] as Timestamp?;
                        final String date = timestamp != null
                            ? DateFormat(
                                'dd MMMM yyyy, HH:mm',
                                'fr_FR', // Use French locale
                              ).format(timestamp.toDate())
                            : 'Date inconnue';

                        return Card(
                          margin: EdgeInsets.only(bottom: verticalSpacing),
                          child: Padding(
                            padding: cardPadding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Technicien: ${data['technicianName']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: fontSize,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: width * 0.025,
                                        vertical: height * 0.006,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(
                                          data['status'] as String,
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _getStatusText(
                                          data['status'] as String,
                                        ),
                                        style: TextStyle(
                                          color: _getStatusColor(
                                            data['status'] as String,
                                          ),
                                          fontWeight: FontWeight.bold,
                                          fontSize: fontSize * 0.95,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: verticalSpacing * 0.5),
                                Text(
                                  'Téléphone: ${data['technicianPhone']}',
                                  style: TextStyle(fontSize: fontSize),
                                ),
                                SizedBox(height: verticalSpacing * 0.5),
                                Text(
                                  'Prix proposé: ${data['price']} DT',
                                  style: TextStyle(
                                    fontSize: priceFontSize,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFe30713),
                                  ),
                                ),
                                SizedBox(height: verticalSpacing * 0.5),
                                Text(
                                  'Données: $date',
                                  style: TextStyle(fontSize: fontSize * 0.95),
                                ),
                                if (data['status'] == 'pending') ...[
                                  SizedBox(height: verticalSpacing),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          // Handle reject bid
                                          FirebaseFirestore.instance
                                              .collection('bids')
                                              .doc(doc.id)
                                              .update({'status': 'rejected'});
                                        },
                                        child: Text(
                                          'Refuser',
                                          style: TextStyle(
                                            color: Color(0xFFe30713),
                                            fontSize: fontSize,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: width * 0.02),
                                      ElevatedButton(
                                        onPressed: () {
                                          // Handle accept bid
                                          FirebaseFirestore.instance
                                              .collection('bids')
                                              .doc(doc.id)
                                              .update({'status': 'accepted'});
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFe30713,
                                          ),
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: width * 0.04,
                                            vertical: height * 0.012,
                                          ),
                                        ),
                                        child: Text(
                                          'Accepter',
                                          style: TextStyle(fontSize: fontSize),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
