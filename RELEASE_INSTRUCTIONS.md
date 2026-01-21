# 🚀 Google Play Store Release Guide

## 1. Create a Release Keystore
You need a cryptographic key to sign your app. **Keep this file secure!** If you lose it, you cannot update your app.

### Run this command in your terminal:
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
*   It will ask for a password. Remember it!
*   It will ask for your details (Name, Org, etc.).
*   It creates a file `upload-keystore.jks` in your home directory.

## 2. Configure `key.properties`
Create a new file named `key.properties` in the `android/` directory (`android/key.properties`).
**Do NOT commit this file to public version control.**

Add the following content (replace with your actual values):
```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/home/mehedi-hasan/upload-keystore.jks
```
*Note: `storeFile` must be the absolute path to your `.jks` file.*

## 3. Build the Release Bundle
Run this command to generate the App Bundle (`.aab`) which Google Play requires:
```bash
flutter build appbundle
```
The output file will be at: `build/app/outputs/bundle/release/app-release.aab`.

## 4. Google Play Console Checklist

### 📍 Location Permissions
Since you use **Background Location**, you must fill out the "Location permissions" declaration:
1.  **Go to:** App Content > Sensitive permissions > Location permissions.
2.  **Select:** "Yes, this app accesses location in the background".
3.  **Video:** You MUST provide a short video verification link (YouTube) showing:
    *   The app triggering the background location feature (e.g., getting a notification when walking into a geofence while the app is closed).
    *   Show the persistent notification in the status bar.

### ⏰ Alarm Permissions
Since you use `SCHEDULE_EXACT_ALARM`:
1.  **Go to:** App Content > Special app access > Alarms & reminders.
2.  **Justification:** Explain that the app's core functionality is a location-based alarm that must ring precisely when the user enters a zone.

### 🛡️ Privacy Policy
You must provide a URL to a privacy policy that explicitly states you collect location data **even when the app is closed** for the purpose of triggering geofence alarms.

### 🗺️ Google Maps API
Ensure your Google Maps API key in Google Cloud Console is restricted to:
*   **Android apps**: Add your package name `com.smart_alarm_manager.smart_alarm_manager` and your **SHA-1 certificate fingerprint**.
    *   Get release SHA-1: `keytool -list -v -keystore ~/upload-keystore.jks -alias upload`
