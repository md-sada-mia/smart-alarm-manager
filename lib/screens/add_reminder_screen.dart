import 'package:flutter/material.dart';
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
  CameraPosition? _initialCameraPosition;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
        _initialCameraPosition = CameraPosition(
          target: _selectedLocation,
          zoom: 15,
        );
        _updateCoordControllers();
      });
    } catch (e) {
      // Fallback or request permission
      print("Location error: $e");
      setState(() {
        _initialCameraPosition = CameraPosition(
          target: _selectedLocation,
          zoom: 15,
        );
        _updateCoordControllers();
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Reminder'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _saveReminder),
        ],
      ),
      body: _initialCameraPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Map Section (Top Half)
                Expanded(
                  flex: 4,
                  child: Stack(
                    children: [
                      GoogleMap(
                        style: Theme.of(context).brightness == Brightness.dark
                            ? null // Add dark style json if needed
                            : null,
                        initialCameraPosition: _initialCameraPosition!,
                        onMapCreated: (controller) =>
                            _mapController = controller,
                        onCameraMove: _onMapCameraMove,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
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
                        // Center Marker is static in UI over the map
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: 30,
                          ), // Adjust for pin tip
                          child: Icon(
                            Icons.location_on,
                            size: 40,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text("Radius: ${_radius.toInt()}m"),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Form Section (Bottom Half)
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(16),
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
                    child: Form(
                      key: _formKey,
                      child: ListView(
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
                          const SizedBox(height: 16),

                          if (_useCoordinates) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _latController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Latitude',
                                    ),
                                    onChanged: (_) => _onCoordChanged(),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _lngController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Longitude',
                                    ),
                                    onChanged: (_) => _onCoordChanged(),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          TextFormField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Title',
                              prefixIcon: Icon(Icons.title),
                              filled: true,
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a title';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descController,
                            decoration: const InputDecoration(
                              labelText: 'Description (Optional)',
                              prefixIcon: Icon(Icons.description),
                              filled: true,
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 24),

                          Text(
                            'Radius',
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

                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _saveReminder,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(
                                _isLoading ? 'Saving...' : 'Set Reminder',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
