# Contributing to YOUChat

First off, thank you for considering contributing to YOUChat! It's people like you that make open-source software such a great community.

## 1. Local Development Setup

YOUChat is a monorepo consisting of a Node.js backend and a Flutter mobile frontend.

### Prerequisites
- [Node.js](https://nodejs.org/en/download/) (v16+)
- [MongoDB](https://www.mongodb.com/try/download/community) (running locally)
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Ngrok](https://ngrok.com/download) (for exposing the backend to the mobile app)

### Backend Setup
1. Open a terminal and navigate to the `server/` directory:
   ```bash
   cd server
   npm install
   ```
2. Create a `.env` file in the `server/` directory:
   ```env
   PORT=3000
   MONGODB_URI=mongodb://localhost:27017/youchat
   JWT_SECRET=your_jwt_secret_here
   ```
3. Place your Firebase Service Account JSON at `server/firebase-service-account.json`.
4. Start the server:
   ```bash
   npm run dev
   ```

### Exposing with Ngrok
1. In a new terminal, run:
   ```bash
   ngrok http 3000
   ```
2. Copy the generated `https://` forwarding URL.

### Frontend Setup
1. Navigate to the `youchat/` directory:
   ```bash
   cd youchat
   flutter pub get
   ```
2. Open `youchat/lib/utils/constants.dart` and update `AppConstants.serverUrl` and `AppConstants.wsUrl` with your new Ngrok URL.
3. Place your `google-services.json` at `youchat/android/app/google-services.json`.
4. Run the app:
   ```bash
   flutter run
   ```

## 2. Pull Request Process
1. Ensure your code compiles locally.
2. Ensure you have run `flutter analyze` and fixed any linting warnings.
3. If you changed the database schema or WebSocket events, please document it in your PR description.
4. Open a Pull Request referencing any related issues.

## 3. Code Style
- **Flutter**: We follow standard Dart formatting. Please run `flutter format .` before committing.
- **Node.js**: We use standard ES6 syntax. Avoid committing `console.log` statements in production routes.

Thank you for contributing!
