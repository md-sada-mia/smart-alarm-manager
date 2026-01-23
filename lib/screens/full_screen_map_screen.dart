import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class FullScreenMapScreen extends StatefulWidget {
  final LatLng initialLocation;
  final double initialRadius;

  const FullScreenMapScreen({
    super.key,
    required this.initialLocation,
    required this.initialRadius,
  });

  @override
  State<FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<FullScreenMapScreen> {
  late LatLng _selectedLocation;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
  }

  void _onMapCameraMove(CameraPosition position) {
    setState(() {
      _selectedLocation = position.target;
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      final newLoc = LatLng(position.latitude, position.longitude);
      setState(() {
        _selectedLocation = newLoc;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(newLoc));
    } catch (e) {
      print("Location error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation,
              zoom: 15,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onCameraMove: _onMapCameraMove,
            onTap: (LatLng pos) {
              setState(() {
                _selectedLocation = pos;
              });
              _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            circles: {
              Circle(
                circleId: const CircleId('radius'),
                center: _selectedLocation,
                radius: widget.initialRadius,
                fillColor: Colors.blue.withOpacity(0.2),
                strokeColor: Colors.blue,
                strokeWidth: 2,
              ),
            },
          ),

          // Center Marker
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Icon(
                Icons.location_on,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),

          // Top Bar (Back Button + Title)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Set Location",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 32,
            right: 16,
            left: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // My Location FAB
                FloatingActionButton(
                  heroTag: "my_loc",
                  onPressed: _getCurrentLocation,
                  backgroundColor: Theme.of(context).cardColor,
                  foregroundColor: Theme.of(context).iconTheme.color,
                  child: const Icon(Icons.my_location),
                ),

                // Confirm FAB
                FloatingActionButton.extended(
                  heroTag: "confirm",
                  onPressed: () {
                    Navigator.pop(context, _selectedLocation);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text("Confirm Location"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
