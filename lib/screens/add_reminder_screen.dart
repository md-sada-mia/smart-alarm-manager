import 'package:flutter/material.dart';
import 'dart:io';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_alarm_manager/data/reminder_repository.dart';
import 'package:smart_alarm_manager/models/reminder.dart';
import 'package:smart_alarm_manager/utils/constants.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_alarm_manager/data/database_helper.dart';
import 'package:smart_alarm_manager/models/suggestion_history.dart';

class AddReminderScreen extends StatefulWidget {
  final Reminder? reminder;
  const AddReminderScreen({super.key, this.reminder});

  @override
  State<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends State<AddReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  final ReminderRepository _repository = ReminderRepository();

  // Form Fields
  final TextEditingController _titleController = TextEditingController();

  // Suggestion State
  List<SuggestionHistory> _locationSuggestions = [];

  // ... existing controllers ...
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

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
  bool _isEditing = false;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  List<int> _selectedDays = [1, 2, 3, 4, 5, 6, 7]; // Default: Every day

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadSuggestions();

    if (widget.reminder != null) {
      _isEditing = true;
      _titleController.text = widget.reminder!.title;
      _descController.text = widget.reminder!.description;
      _selectedLocation = LatLng(
        widget.reminder!.latitude,
        widget.reminder!.longitude,
      );
      _radius = widget.reminder!.radius;

      // Parse Time Range
      if (widget.reminder!.startTime != null &&
          widget.reminder!.endTime != null) {
        final startParts = widget.reminder!.startTime!.split(':');
        final endParts = widget.reminder!.endTime!.split(':');
        _startTime = TimeOfDay(
          hour: int.parse(startParts[0]),
          minute: int.parse(startParts[1]),
        );
        _endTime = TimeOfDay(
          hour: int.parse(endParts[0]),
          minute: int.parse(endParts[1]),
        );
      }

      if (widget.reminder!.days != null && widget.reminder!.days!.isNotEmpty) {
        _selectedDays = List.from(widget.reminder!.days!);
      }

      _updateCoordControllers();
    } else {
      _getCurrentLocation();
    }

    _initialCameraPosition = CameraPosition(
      target: _selectedLocation,
      zoom: 15,
    );
  }

  Future<void> _loadSuggestions() async {
    final suggestions = await DatabaseHelper().getAllHistory();
    if (mounted) {
      setState(() {
        _locationSuggestions = suggestions;
      });
    }
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
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(_selectedLocation),
        );
      }
    } catch (e) {
      // Fallback or request permission
      print("Location error: $e");
      // Keep default location
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

  Future<void> _pickTimeRange() async {
    final TimeOfDay? start = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: "Select Start Time",
    );
    if (start != null) {
      if (!mounted) return;
      final TimeOfDay? end = await showTimePicker(
        context: context,
        initialTime: _endTime ?? const TimeOfDay(hour: 17, minute: 0),
        helpText: "Select End Time",
      );
      if (end != null) {
        setState(() {
          _startTime = start;
          _endTime = end;
        });
      }
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  Future<void> _saveReminder() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final reminder = Reminder(
        id: widget.reminder?.id, // Preserve ID if editing
        title: _titleController.text,
        description: _descController.text,
        latitude: _selectedLocation.latitude,
        longitude: _selectedLocation.longitude,
        radius: _radius,
        createdAt: widget.reminder?.createdAt ?? DateTime.now(),
        isActive: widget.reminder?.isActive ?? true,
        status: widget.reminder?.status ?? ReminderStatus.active,
        startTime: _startTime != null ? _formatTimeOfDay(_startTime!) : null,
        endTime: _endTime != null ? _formatTimeOfDay(_endTime!) : null,
        days: _selectedDays.length == 7
            ? null
            : _selectedDays, // Null if all days selected
      );

      if (_isEditing) {
        await _repository.updateReminder(reminder);
      } else {
        await _repository.addReminder(reminder);
      }

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

  String _getDaysSummary() {
    if (_selectedDays.length == 7) return "Every Day";
    if (_selectedDays.isEmpty) return "Never";
    if (_selectedDays.length == 2 &&
        _selectedDays.contains(6) &&
        _selectedDays.contains(7)) {
      return "Weekends";
    }
    if (_selectedDays.length == 5 &&
        ![6, 7].any((d) => _selectedDays.contains(d))) {
      return "Weekdays";
    }

    // Sort days
    final List<int> sorted = List.from(_selectedDays)..sort();
    final List<String> shortNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return sorted.map((d) => shortNames[d - 1]).join(", ");
  }

  Future<void> _showDayPickerDialog() async {
    // Temp state for the dialog
    List<int> tempSelectedDays = List.from(_selectedDays);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Repeat Days"),
              content: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: List.generate(7, (index) {
                  final dayIndex = index + 1;
                  final fullNames = [
                    'Monday',
                    'Tuesday',
                    'Wednesday',
                    'Thursday',
                    'Friday',
                    'Saturday',
                    'Sunday',
                  ];
                  final isSelected = tempSelectedDays.contains(dayIndex);
                  return FilterChip(
                    label: Text(fullNames[index]),
                    selected: isSelected,
                    onSelected: (bool selected) {
                      setDialogState(() {
                        if (selected) {
                          tempSelectedDays.add(dayIndex);
                          tempSelectedDays.sort();
                        } else {
                          if (tempSelectedDays.length > 1) {
                            tempSelectedDays.remove(dayIndex);
                          } else {
                            // Don't allow empty generic selection inside dialog just yet,
                            // or show toast.
                          }
                        }
                      });
                    },
                  );
                }),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedDays = tempSelectedDays;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("OK"),
                ),
              ],
            );
          },
        );
      },
    );
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
        title: Text(_isEditing ? 'Edit Reminder' : 'New Reminder'),
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
                    decoration: InputDecoration(
                      labelText: 'Title',
                      prefixIcon: const Icon(Icons.title),
                      filled: true,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: PopupMenuButton<SuggestionHistory>(
                        icon: const Icon(Icons.history),
                        onSelected: (SuggestionHistory selection) {
                          setState(() {
                            _titleController.text = selection.title;
                            _selectedLocation = LatLng(
                              selection.latitude,
                              selection.longitude,
                            );
                            _updateCoordControllers();
                          });
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLng(_selectedLocation),
                          );
                        },
                        itemBuilder: (BuildContext context) {
                          return _locationSuggestions.map((
                            SuggestionHistory choice,
                          ) {
                            return PopupMenuItem<SuggestionHistory>(
                              value: choice,
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          choice.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Used ${choice.usageCount} times',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList();
                        },
                      ),
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

          // Combined Compact Row for Time & Repeat
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Time Section
                Expanded(
                  child: InkWell(
                    onTap: _pickTimeRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.grey,
                              ),
                              SizedBox(width: 4),
                              Text(
                                "Time",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _startTime != null && _endTime != null
                                ? "${_startTime!.format(context)} - ${_endTime!.format(context)}"
                                : "Always Active",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  height: 32,
                  width: 1,
                  color: Colors.grey.withOpacity(0.3),
                ),

                // Repeat Section
                Expanded(
                  child: InkWell(
                    onTap: _showDayPickerDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.repeat, size: 16, color: Colors.grey),
                              SizedBox(width: 4),
                              Text(
                                "Repeat",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getDaysSummary(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 4. Middle Section: Map (Expanded)
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
