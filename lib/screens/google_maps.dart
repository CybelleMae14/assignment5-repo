import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FavoritePlace {
  final String placeName;
  final String description;
  final LatLng position;
  String? docId; // New property to store the document ID

  FavoritePlace({
    required this.placeName,
    required this.description,
    required this.position,
    required this.docId,
  });
}

class GoogleMapsScreen extends StatefulWidget {
  const GoogleMapsScreen({Key? key}) : super(key: key);

  @override
  State<GoogleMapsScreen> createState() => _GoogleMapsScreen();
}

class _GoogleMapsScreen extends State<GoogleMapsScreen> {
  static final LatLng _initialPosition =
      LatLng(15.98136625534374, 120.57155419700595);

  late GoogleMapController _mapController;

  List<Marker> _markers = [];
  List<FavoritePlace> _favoritePlaces = [];

  Future<String> getPlaceName(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark placemark = placemarks[0];
        String name = placemark.name ?? '';
        String locality = placemark.locality ?? '';
        String subAdministrativeArea = placemark.subAdministrativeArea ?? '';

        return '$name, $locality, $subAdministrativeArea';
      }
    } catch (e) {
      print('Error retrieving place name: $e');
    }
    return '';
  }

  Future<bool> checkServicePermission() async {
    LocationPermission locationPermission;

    var serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Location service is disabled. Please enable it in the Settings.'),
        ),
      );
      return false;
    }

    locationPermission = await Geolocator.checkPermission();

    if (locationPermission == LocationPermission.denied) {
      locationPermission = await Geolocator.requestPermission();
      if (locationPermission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Location permission is denied. You cannot use the app without allowing location permission.'),
          ),
        );
        return false;
      }
    }

    if (locationPermission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Location permission is denied. Please enable it in the settings.'),
        ),
      );
      return false;
    }
    return true;
  }

  void placeMarker(LatLng pos) {
    //_markers.clear();
    _favoritePlaces.forEach((place) {
      _markers.add(
        Marker(
          markerId:
              MarkerId('${place.position.latitude}${place.position.longitude}'),
          position: place.position,
          infoWindow:
              InfoWindow(title: place.placeName, snippet: place.description),
        ),
      );
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        String description = '';
        return FutureBuilder<String>(
          future: getPlaceName(pos.latitude, pos.longitude),
          builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: Text('Loading...'),
                content: CircularProgressIndicator(),
              );
            } else if (snapshot.hasData) {
              String placeName = snapshot.data!;
              return AlertDialog(
                title: Text('Add Place'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Place: $placeName'),
                    TextField(
                      onChanged: (value) {
                        description = value;
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter a description',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      FavoritePlace newPlace = FavoritePlace(
                        placeName: placeName,
                        description: description,
                        position: pos,
                        docId: '',
                      );

                      try {
                        DocumentReference docRef = await FirebaseFirestore
                            .instance
                            .collection('favorite_places')
                            .add({
                          'placeName': newPlace.placeName,
                          'description': newPlace.description,
                          'latitude': newPlace.position.latitude,
                          'longitude': newPlace.position.longitude,
                        });
                        newPlace.docId = docRef
                            .id; // Assign the document ID to the new place

                        setState(() {
                          _favoritePlaces.add(newPlace);
                          updateMarkers(); // Update the markers after adding a new place
                        });

                        Navigator.of(context).pop();
                      } catch (e) {
                        print('Error saving favorite place: $e');
                        // Handle the error
                      }
                    },
                    child: Text('Add'),
                  ),
                ],
              );
            } else {
              return AlertDialog(
                title: Text('Error'),
                content: Text('Failed to retrieve place name.'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text('OK'),
                  ),
                ],
              );
            }
          },
        );
      },
    );

    CameraPosition _cameraPosition = CameraPosition(target: pos, zoom: 18);
    _mapController
        .animateCamera(CameraUpdate.newCameraPosition(_cameraPosition));
  }

  void deleteMarker(FavoritePlace place) async {
    print('deleted');
    try {
      await FirebaseFirestore.instance
          .collection('favorite_places')
          .doc(place.docId)
          .delete();
      setState(() {
        _favoritePlaces.remove(place);
        _markers.removeWhere((marker) =>
            marker.markerId.value ==
            '${place.position.latitude}${place.position.longitude}');
      });
    } catch (e) {
      print('Error deleting favorite place: $e');
      // Handle the error
    }
  }

  Future<void> fetchFavoritePlaces() async {
    try {
      QuerySnapshot snapshot =
          await FirebaseFirestore.instance.collection('favorite_places').get();
      List<FavoritePlace> favoritePlaces = snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return FavoritePlace(
          placeName: data['placeName'],
          description: data['description'],
          position: LatLng(data['latitude'], data['longitude']),
          docId: doc
              .id, // Retrieve the document ID and assign it to the favorite place
        );
      }).toList();
      setState(() {
        _favoritePlaces = favoritePlaces;
        updateMarkers(); // Update the markers after retrieving the favorite places
      });
    } catch (e) {
      print('Error fetching favorite places: $e');
      // Handle the error
    }
  }

  void updateMarkers() {
    _markers.clear();
    _favoritePlaces.forEach((place) {
      _markers.add(
        Marker(
          markerId:
              MarkerId('${place.position.latitude}${place.position.longitude}'),
          position: place.position,
          infoWindow:
              InfoWindow(title: place.placeName, snippet: place.description),
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    fetchFavoritePlaces();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GoogleMap(
          mapType: MapType.hybrid,
          zoomControlsEnabled: true,
          myLocationButtonEnabled: true,
          myLocationEnabled: true,
          initialCameraPosition: CameraPosition(
            target: _initialPosition,
            zoom: 17,
            bearing: 0,
            tilt: 0,
          ),
          onTap: (pos) {
            print(pos);
            placeMarker(pos);
          },
          onMapCreated: (controller) {
            _mapController = controller;
          },
          markers: _markers.toSet(),
        ),
      ),
      floatingActionButton: Align(
        alignment: Alignment.bottomCenter,
        child: FloatingActionButton(
          onPressed: () async {
            final deletedPlace = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FavoritePlacesScreen(
                  favoritePlaces: _favoritePlaces,
                  onDeletePlace: deleteMarker,
                ),
              ),
            );

            if (deletedPlace != null) {
              deleteMarker(deletedPlace);
            }
          },
          child: Icon(Icons.list),
        ),
      ),
    );
  }
}

//Favorite Places
class FavoritePlacesScreen extends StatelessWidget {
  final List<FavoritePlace> favoritePlaces;
  final Function(FavoritePlace) onDeletePlace;

  const FavoritePlacesScreen({
    Key? key,
    required this.favoritePlaces,
    required this.onDeletePlace,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Favorite Places'),
      ),
      body: ListView.builder(
        itemCount: favoritePlaces.length,
        itemBuilder: (context, index) {
          final place = favoritePlaces[index];
          return ListTile(
            title: Text(place.placeName),
            subtitle: Text(place.description),
            trailing: IconButton(
              icon: Icon(Icons.delete),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('Delete Place'),
                      content:
                          Text('Are you sure you want to delete this place?'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => GoogleMapsScreen(),
                                ));
                            onDeletePlace(place);
                          },
                          child: Text('Delete'),
                        ),
                      ],
                    );
                  },
                ).then((value) {
                  if (value != null) {
                    onDeletePlace(value);
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }
}
