const mongoose = require('mongoose');

/**
 * PendingMessage — stores undelivered messages in MongoDB.
 * When recipient is offline, messages are persisted here instead of
 * the in-memory map (which had only 60s TTL).
 *
 * TTL: Auto-deletes after 24 hours via MongoDB TTL index.
 * On reconnect: all pending messages for a user are delivered, then deleted.
 */
const pendingMessageSchema = new mongoose.Schema({
  messageId: {
    type: String,
    required: true,
    index: true,
  },
  from: {
    type: String,
    required: true,
  },
  to: {
    type: String,
    required: true,
    index: true,
  },
  type: {
    type: String,
    required: true,
    default: 'message', // 'message' or 'group_message'
  },
  groupId: {
    type: String,
    default: null,
  },
  content: {
    type: String,
    default: '',
  },
  mediaUrl: {
    type: String,
    default: null,
  },
  mediaType: {
    type: String,
    default: null,
  },
  originalName: {
    type: String,
    default: null,
  },
  encryptedKey: {
    type: String,
    default: null,
  },
  voiceDuration: {
    type: Number,
    default: null,
  },
  timestamp: {
    type: Number, // milliseconds since epoch
    required: true,
  },
  createdAt: {
    type: Date,
    default: Date.now,
    expires: 86400, // TTL: auto-delete after 24 hours (86400 seconds)
  },
});

// Compound index for fast lookups
pendingMessageSchema.index({ to: 1, createdAt: 1 });

module.exports = mongoose.model('PendingMessage', pendingMessageSchema);
