import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'widgets/custom_app_bar.dart';
import 'request_bids_page.dart';

class HistoriqueClientPage extends StatefulWidget {
  const HistoriqueClientPage({super.key});

  @override
  State<HistoriqueClientPage> createState() => _HistoriqueClientPageState();
}

class _HistoriqueClientPageState extends State<HistoriqueClientPage> {
  String _selectedFilter = 'all';

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'En attente';
      case 'accepted':
        return 'Accepté';
      case 'in_progress':
        return 'En cours';
      case 'completed':
        return 'Terminé';
      case 'cancelled':
        return 'Annulé';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Color(0xFFe30713);
      default:
        return Colors.grey;
    }
  }

  String _formatAddress(String? address) {
    if (address == null || address.isEmpty) {
      return 'Adresse inconnue';
    }

    // Common English to French translations for address components
    final translations = {
      'street': 'rue',
      'avenue': 'avenue',
      'boulevard': 'boulevard',
      'road': 'route',
      'lane': 'allée',
      'square': 'place',
      'district': 'quartier',
      'neighborhood': 'quartier',
      'city': 'ville',
      'town': 'ville',
      'village': 'village',
      'state': 'région',
      'province': 'province',
      'postal code': 'code postal',
      'zip code': 'code postal',
      'country': 'pays',
    };

    String formattedAddress = address;

    // Replace common English terms with French
    translations.forEach((english, french) {
      formattedAddress = formattedAddress.replaceAll(
        RegExp(english, caseSensitive: false),
        french,
      );
    });

    // Capitalize first letter of each word
    formattedAddress = formattedAddress
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');

    return formattedAddress;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Utilisateur non connecté')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CustomAppBar(
        title: '',
        showBackButton: true,
        showImage: true,
      ),
      body: Column(
        children: [
          // Filter Options
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterChip('Tous', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('En attente', 'pending'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Accepté', 'accepted'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Rejeté', 'rejected'),
                ],
              ),
            ),
          ),

          // Requests List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('requests')
                  .where('userId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucune intervention trouvée',
                      style: TextStyle(fontSize: 16, fontFamily: 'Poppins'),
                    ),
                  );
                }

                // Filter and sort the documents
                final filteredDocs =
                    snapshot.data!.docs.where((doc) {
                      if (_selectedFilter == 'all') return true;
                      final data = doc.data() as Map<String, dynamic>;
                      return data['status'] == _selectedFilter;
                    }).toList()..sort((a, b) {
                      final aData = a.data() as Map<String, dynamic>;
                      final bData = b.data() as Map<String, dynamic>;
                      final aTime = aData['createdAt'] as Timestamp?;
                      final bTime = bData['createdAt'] as Timestamp?;
                      if (aTime == null || bTime == null) return 0;
                      return bTime.compareTo(aTime); // Descending order
                    });

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Text(
                      'Aucune intervention ${_selectedFilter == 'all' ? '' : _getStatusText(_selectedFilter)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
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

                    // Get location
                    final GeoPoint? location = data['location'] as GeoPoint?;
                    final String locationStr = location != null
                        ? '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}'
                        : 'Position inconnue';

                    // Get and format place name
                    final String placeName = _formatAddress(
                      data['placeName'] as String?,
                    );

                    // Get description
                    final String description =
                        data['description'] as String? ?? 'Aucune description';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),
                      child: ListTile(
                        leading: const Icon(
                          Icons.bolt,
                          color: Color(0xFFe30713),
                        ),
                        title: Text(
                          placeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Données : $date"),
                            Text("Description : $description"),
                            Text(
                              "État : ${_getStatusText(data['status'] as String? ?? 'pending')}",
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          Icons.circle,
                          size: 12,
                          color: _getStatusColor(
                            data['status'] as String? ?? 'pending',
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RequestBidsPage(
                                requestId: doc.id,
                                requestData: data,
                              ),
                            ),
                          );
                        },
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
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (bool selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFe30713),
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}
