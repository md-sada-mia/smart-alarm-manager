# Smart Alarm Manager 📍⏰ 

**Smart Alarm Manager** is a powerful location-based reminder application built with Flutter. It ensures you never miss a task when you arrive at a specific destination. Whether it's picking up groceries, arriving at work, or reaching a travel destination, Smart Alarm Manager wakes you up (literally!) when you get there.

## 🌟 Key Features

*   **📍 Location-Based Alarms**: Triggers a full-screen alarm and notification when you enter a specific radius of a location.
*   **🕒 Time Ranges**: Set optional "Active Hours" for your reminders. The alarm will only trigger if you arrive *and* the current time is within your specified range (e.g., "9:00 AM - 5:00 PM").
*   **📅 Day-wise Scheduling (NEW!)**: Choose specific days of the week for your reminders to be active (e.g., "Weekdays", "Weekends", or "Every Mon, Wed, Fri").
*   **🧠 Smart Suggestions**: The app learns from your history! It suggests frequently used titles and locations to make adding reminders lightning fast.
*   **🏃‍♂️ Background Tracking**: Reliable background service ensures you get notified even if the app is closed or your phone is locked.
*   **📶 Offline Capable**: Works without an internet connection using cached maps and local database storage.
*   **⭕ Customizable Radius**: Adjust the geofence radius (from 100m to 2km) to suit your needs.
*   **😴 Snooze Functionality**: Not ready to deal with the reminder? Snooze the alarm for 5, 10, or 15 minutes.
*   **🗺️ Interactive Map**: Use Google Maps to pinpoint exact locations with "My Location" support.

## 📸 Screenshots

| Home Screen | Add Reminder | Alarm Screen |
|:---:|:---:|:---:|
| *(Add screenshot here)* | *(Add screenshot here)* | *(Add screenshot here)* |

## 🛠️ Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/yourusername/smart_alarm_manager.git
    ```
2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```
3.  **Setup Google Maps API:**
    *   Get an API Key from Google Cloud Console.
    *   Add it to `android/app/src/main/AndroidManifest.xml` and `ios/Runner/AppDelegate.swift`.
4.  **Run the app:**
    ```bash
    flutter run
    ```

## 📱 Permissions

The app requires the following permissions to function correctly:
*   **Location (Always Allow)**: Essential for background tracking.
*   **Notification**: To show alerts when you arrive.
*   **Overlay (Display over other apps)**: To show the full-screen alarm when the phone is locked.
*   **Exact Alarm**: To schedule timely checks.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
*Built with ❤️ using Flutter*
