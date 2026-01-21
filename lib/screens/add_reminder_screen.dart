import 'package:flutter/material.dart';
import 'dart:io';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_alarm_manager/data/reminder_repository.dart';
import 'package:smart_alarm_manager/models/reminder.dart';
import 'package:smart_alarm_manager/utils/constants.dart';
import 'package:geolocator/geolocator.dart';

class AddReminderScreen extends StatefulWidget {
  const AddReminderScreen({super.key});

  @override
  State<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends State<AddReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  final ReminderRepository _repository = ReminderRepository();

  // Form Fields
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController =
      TextEditingController(); // Fixed type-o

  // State
  bool _useCoordinates = false;
  double _radius = AppConstants.defaultGeofenceRadius;
  LatLng _selectedLocation = const LatLng(
    37.422,
    -122.084,
  ); // Default (Googleplex)
  bool _isLoading = false;
  bool _isOffline = false;
  late CameraPosition _initialCameraPosition;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    // Initialize with default immediately for instant load
    _initialCameraPosition = CameraPosition(
      target: _selectedLocation,
      zoom: 15,
    );
    _checkConnectivity();
    _getCurrentLocation();
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        if (mounted) setState(() => _isOffline = false);
      }
    } catch (_) {
      // Not connected
      if (mounted) {
        setState(() => _isOffline = true);
        // Also show snackbar for visibility
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "we need internet just 1 time for point you locaion else you are get alarm without internet.",
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
        // We don't change _initialCameraPosition after init, we move controller
        _updateCoordControllers();
      });
    } catch (e) {
      // Fallback or request permission
      print("Location error: $e");
      // Keep default location
    }

    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(_selectedLocation));
    }
  }

  void _updateCoordControllers() {
    _latController.text = _selectedLocation.latitude.toStringAsFixed(6);
    _lngController.text = _selectedLocation.longitude.toStringAsFixed(6);
  }

  void _onMapCameraMove(CameraPosition position) {
    if (!_useCoordinates) {
      setState(() {
        _selectedLocation = position.target;
        _updateCoordControllers();
      });
    }
  }

  void _onCoordChanged() {
    double? lat = double.tryParse(_latController.text);
    double? lng = double.tryParse(_lngController.text);
    if (lat != null && lng != null) {
      setState(() {
        _selectedLocation = LatLng(lat, lng);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(_selectedLocation));
    }
  }

  Future<void> _saveReminder() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final reminder = Reminder(
        title: _titleController.text,
        description: _descController.text,
        latitude: _selectedLocation.latitude,
        longitude: _selectedLocation.longitude,
        radius: _radius,
        createdAt: DateTime.now(),
      );

      await _repository.addReminder(reminder);

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context);
      }
    }
  }

  void _zoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  void _zoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  Widget _buildMapControl({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Icon(
            icon,
            color:
                Theme.of(context).iconTheme.color?.withOpacity(0.7) ??
                Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Reminder'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _saveReminder),
        ],
      ),
      body: Column(
        children: [
          // 1. Top Section: Inputs
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Toggle
                  Center(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Map'),
                          icon: Icon(Icons.map),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Coordinates'),
                          icon: Icon(Icons.edit_location),
                        ),
                      ],
                      selected: {_useCoordinates},
                      onSelectionChanged: (Set<bool> newSelection) {
                        setState(() {
                          _useCoordinates = newSelection.first;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_useCoordinates) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _latController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Latitude',
                              isDense: true,
                            ),
                            onChanged: (_) => _onCoordChanged(),
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _lngController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Longitude',
                              isDense: true,
                            ),
                            onChanged: (_) => _onCoordChanged(),
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      prefixIcon: Icon(Icons.title),
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a title';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      prefixIcon: Icon(Icons.description),
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),

          // 2. Middle Section: Map (Expanded)
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  style: Theme.of(context).brightness == Brightness.dark
                      ? null // Add dark style json if needed
                      : null,
                  initialCameraPosition: _initialCameraPosition,
                  onMapCreated: (controller) => _mapController = controller,
                  onCameraMove: _onMapCameraMove,
                  onTap: (LatLng pos) {
                    setState(() {
                      _selectedLocation = pos;
                      _updateCoordControllers();
                    });
                    _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false, // We use custom FAB
                  zoomControlsEnabled: false, // We use custom buttons
                  circles: {
                    Circle(
                      circleId: const CircleId('radius'),
                      center: _selectedLocation,
                      radius: _radius,
                      fillColor: Colors.blue.withOpacity(0.2),
                      strokeColor: Colors.blue,
                      strokeWidth: 2,
                    ),
                  },
                ),

                // Offline Message Overlay
                if (_isOffline)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            "we need internet just 1 time for point you locaion else you are get alarm without internet.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

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
                // Custom Map Controls (My Location + Zoom)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMapControl(
                        icon: Icons.my_location,
                        onPressed: _getCurrentLocation,
                      ),
                      const SizedBox(height: 8), // Gap between groups
                      _buildMapControl(icon: Icons.add, onPressed: _zoomIn),
                      _buildMapControl(icon: Icons.remove, onPressed: _zoomOut),
                    ],
                  ),
                ),
                // Radius Badge - Moved to Top Left
                Positioned(
                  top: 16,
                  left: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text("Radius: ${_radius.toInt()}m"),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Bottom Section: Controls
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                // Slider Section (Expanded)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Radius: ${_radius.toInt()}m',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Slider(
                        value: _radius,
                        min: 100,
                        max: 2000,
                        divisions: 19,
                        label: "${_radius.toInt()}m",
                        onChanged: (value) {
                          setState(() {
                            _radius = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // FAB Section
                FloatingActionButton(
                  onPressed: _isLoading ? null : _saveReminder,
                  elevation: 4,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
