const logger = require('../utils/logger');

/**
 * Server-side Deletion Enforcer.
 * Manages the 7-second deletion timer for read messages.
 * Ensures messages are deleted even if clients disconnect.
 *
 * Supports:
 * - 1:1 deletion (both sender + receiver deleted simultaneously)
 * - Group per-user deletion (each reader's copy deleted individually)
 */
class DeletionEnforcer {
  constructor() {
    // Map<messageId, { timer, senderId, receiverId, timestamp }> — for 1:1
    this.pendingDeletions = new Map();
    // Map<`${messageId}_${userId}`, { timer, timestamp }> — for per-user group deletion
    this.pendingGroupDeletions = new Map();
    // Map<userId, Set<messageId>> — messages to delete when user reconnects
    this.offlineDeletions = new Map();
  }

  /**
   * Start a 7-second deletion timer for a 1:1 message.
   * @param {string} messageId
   * @param {string} senderId
   * @param {string} receiverId
   * @param {Function} onDelete - Callback when timer expires
   */
  startTimer(messageId, senderId, receiverId, onDelete) {
    // Clear any existing timer for this message
    this.cancelTimer(messageId);

    const timer = setTimeout(() => {
      logger.debug(`Deletion timer expired: ${messageId}`);
      this.pendingDeletions.delete(messageId);
      onDelete(messageId, senderId, receiverId);
    }, 15000); // 15 seconds

    this.pendingDeletions.set(messageId, {
      timer,
      senderId,
      receiverId,
      timestamp: Date.now(),
    });

    logger.debug(`Deletion timer started: ${messageId} (15s)`);
  }

  /**
   * Start a per-user 7-second deletion timer for a group message.
   * Only affects this specific reader — other group members are unaffected.
   * @param {string} messageId
   * @param {string} readerId - the user who just read the message
   * @param {Function} onDelete - Callback(messageId, readerId)
   */
  startGroupTimer(messageId, readerId, onDelete) {
    const key = `${messageId}_${readerId}`;

    // Clear existing timer for this user+message combo
    this.cancelGroupTimer(key);

    const timer = setTimeout(() => {
      logger.debug(`Group deletion timer expired: ${messageId} for ${readerId}`);
      this.pendingGroupDeletions.delete(key);
      onDelete(messageId, readerId);
    }, 15000);

    this.pendingGroupDeletions.set(key, {
      timer,
      timestamp: Date.now(),
    });

    logger.debug(`Group deletion timer started: ${messageId} for ${readerId} (15s)`);
  }

  /**
   * Cancel a pending 1:1 deletion timer.
   */
  cancelTimer(messageId) {
    const pending = this.pendingDeletions.get(messageId);
    if (pending) {
      clearTimeout(pending.timer);
      this.pendingDeletions.delete(messageId);
    }
  }

  /**
   * Cancel a pending per-user group deletion timer.
   */
  cancelGroupTimer(key) {
    const pending = this.pendingGroupDeletions.get(key);
    if (pending) {
      clearTimeout(pending.timer);
      this.pendingGroupDeletions.delete(key);
    }
  }

  /**
   * Mark a message for deletion when a user reconnects.
   * Used when the user is offline during timer expiry.
   */
  addOfflineDeletion(userId, messageId) {
    if (!this.offlineDeletions.has(userId)) {
      this.offlineDeletions.set(userId, new Set());
    }
    this.offlineDeletions.get(userId).add(messageId);
    logger.debug(`Offline deletion queued: ${messageId} for ${userId}`);
  }

  /**
   * Get and clear all pending offline deletions for a user.
   * Called when user reconnects.
   */
  getOfflineDeletions(userId) {
    const deletions = this.offlineDeletions.get(userId);
    if (deletions) {
      const messageIds = Array.from(deletions);
      this.offlineDeletions.delete(userId);
      return messageIds;
    }
    return [];
  }

  /**
   * Acknowledgment that a client has deleted a message.
   */
  acknowledgeDelete(messageId, userId) {
    logger.debug(`Delete acknowledged: ${messageId} by ${userId}`);
    // Remove from offline queue if present
    const userDeletions = this.offlineDeletions.get(userId);
    if (userDeletions) {
      userDeletions.delete(messageId);
      if (userDeletions.size === 0) {
        this.offlineDeletions.delete(userId);
      }
    }
  }

  /**
   * Get stats for monitoring.
   */
  getStats() {
    return {
      pendingTimers: this.pendingDeletions.size,
      pendingGroupTimers: this.pendingGroupDeletions.size,
      usersWithOfflineDeletions: this.offlineDeletions.size,
    };
  }
}

module.exports = DeletionEnforcer;
