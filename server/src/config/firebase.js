const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const logger = require('../utils/logger');

let firebaseApp = null;

const initializeFirebase = () => {
  const serviceAccountPath = path.join(__dirname, '../../firebase-service-account.json');
  
  if (fs.existsSync(serviceAccountPath)) {
    try {
      const serviceAccount = require(serviceAccountPath);
      firebaseApp = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
      logger.info('Firebase Admin SDK initialized successfully.');
    } catch (error) {
      logger.error('Error initializing Firebase Admin SDK: ' + error.message);
    }
  } else {
    logger.warn('firebase-service-account.json not found. FCM notifications will be disabled.');
  }
};

const getFirebaseApp = () => firebaseApp;

module.exports = {
  initializeFirebase,
  getFirebaseApp
};
