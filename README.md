# YOUChat Deployment Guide 🚀

This guide explains how to spin up the local Node.js backend to the internet using **Ngrok**, how to link it to your Flutter app, and how to build the APK so you can chat securely with friends anywhere in the world.

---

## 🏗 System Architecture

1. **Backend (`/server`)**: A Node.js + Express + WebSockets server communicating with a MongoDB database. Runs strictly locally on port 3000.
2. **Frontend (`/youchat`)**: A decentralized Flutter mobile client. Communicates with both HTTP APIs (Auth/Keys) and WebSockets (Live Messaging).
3. **Tunneling (Ngrok)**: Exposes the backend's local port (`3000`) out to the internet through a public HTTPS and WSS tunnel so that clients not connected to the local Wi-Fi can still reach the server.

---

## 🏃 1. Start the Local Server

Open a terminal and navigate to the `server` directory, then activate the server.

```bash
cd server
npm run dev
```

> **Note**: Make sure your local MongoDB instance is running (usually on `localhost:27017` or `27018`).

---

## 🌐 2. Expose the Server using Ngrok

Open a **separate** terminal window and run `ngrok` pointing to your backend's port.

```bash
ngrok http 3000
```

Ngrok will initialize and provide you with a forwarding URL. It will look something like this:
`https://itzel-fingered-lavina.ngrok-free.dev -> http://localhost:3000`

Copy the generated `https://...` URL.

> **Important**: This terminal must stay open! If you close it, the ngrok tunnel will die, and the app will lose connection to the server.

---

## 🔗 3. Connect the Flutter App

Navigate to your Flutter app's constant file where the API routing is decided:
`youchat/lib/utils/constants.dart`

Modify the endpoints under `AppConstants` to use your brand new ngrok URL.
*Replace the URLs with your exact Ngrok ID.*

```dart
class AppConstants {
  // Use HTTPS for standard API calls
  static const String serverUrl = 'https://itzel-fingered-lavina.ngrok-free.dev';
  
  // Use WSS (Secure WebSocket) for real-time messaging
  static const String wsUrl = 'wss://itzel-fingered-lavina.ngrok-free.dev';
  
  // ... rest of the code
}
```

---

## 📦 4. Build the Android APK

Build a Release APK that packages up your Flutter code with the new Ngrok internet routing.

```bash
cd youchat
flutter build apk --release
```

Once parsing and gradle assembling executes completely, the built package will be located at:
`youchat/build/app/outputs/flutter-apk/app-release.apk`

---

## 🚀 5. Distribute & Connect

1. Take the `app-release.apk` file and send it to your friends (WhatsApp, Email, Telegram, thumb drive).
2. Ensure your laptop remains turned on with BOTH the `npm run dev` and `ngrok` terminal windows running actively.
3. Have your friends install the APK and sign in! As long as the tunnel exists on your laptop, the app will facilitate real-time chat with "Dark Evil" UI from their smartphone securely back to your backend.

### 🔄 Restarting / New Sessions (Free Ngrok)
Free-tier Ngrok sessions often expire after exactly 2 hours of connectivity or when the laptop goes to sleep.
If this happens:
1. Kill the ngrok terminal window.
2. Restart it via `ngrok http 3000`.
3. If it generates a *new* randomized URL string, **you must repeat step 3 and 4**, rebuilding the APK and giving your friends the newly compiled application. No old data will be lost, they will just need the new routing instructions.
