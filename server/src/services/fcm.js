const { getFirebaseApp } = require('../config/firebase');
const admin = require('firebase-admin');
const User = require('../models/User');
const logger = require('../utils/logger');

/**
 * Send an FCM notification when a user receives a message while offline.
 * Maintains E2EE by only sending the sender's userId, not the message content.
 * 
 * @param {string} toUserId - The recipient's userId
 * @param {string} fromUserId - The sender's userId
 * @param {string} type - 'message' or 'group_message'
 * @param {string} groupId - (Optional) The group ID for group messages
 */
const sendOfflineNotification = async (toUserId, fromUserId, type = 'message', groupId = null) => {
  const app = getFirebaseApp();
  
  // If Firebase wasn't initialized (missing service account json), skip.
  if (!app) return;

  try {
    const user = await User.findOne({ userId: toUserId });
    
    if (!user || !user.fcmToken) {
      return; // No FCM token for the user
    }

    const payload = {
      token: user.fcmToken,
      notification: {
        title: 'YOUchat',
        body: type === 'group_message' 
            ? `New message in ${groupId} from ${fromUserId}` 
            : `New message from ${fromUserId}`
      },
      data: {
        type: type,
        fromUserId: fromUserId,
        groupId: groupId || '',
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'high_importance_channel'
        }
      }
    };

    const response = await admin.messaging().send(payload);
    logger.info(`FCM notification sent to ${toUserId}: ${response}`);
  } catch (error) {
    // If token is invalid/unregistered, we could remove it from the DB here
    if (error.code === 'messaging/registration-token-not-registered') {
      logger.info(`FCM token expired for ${toUserId}, removing it.`);
      await User.updateOne({ userId: toUserId }, { $unset: { fcmToken: "" } });
    } else {
      logger.error(`Error sending FCM to ${toUserId}: ${error.message}`);
    }
  }
};

module.exports = {
  sendOfflineNotification
};
