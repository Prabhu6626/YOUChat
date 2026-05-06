const mongoose = require('mongoose');

/**
 * Group Schema — stores group metadata and members.
 * Messages are NOT stored — relayed in-memory only (same as 1:1).
 */
const groupSchema = new mongoose.Schema(
  {
    groupId: {
      type: String,
      required: true,
      unique: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
      minlength: 1,
      maxlength: 50,
    },
    creatorId: {
      type: String,
      required: true,
    },
    members: [
      {
        type: String, // userIds
      },
    ],
    admins: [
      {
        type: String // userIds
      }
    ],
    groupPictureUrl: {
      type: String,
      default: null,
    },
    settings: {
      editGroupInfo: {
        type: String,
        enum: ['all', 'admins'],
        default: 'all',
      },
      sendMessages: {
        type: String,
        enum: ['all', 'admins'],
        default: 'all',
      },
    },
    createdAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    versionKey: false,
  }
);

// Index for fast member lookup
groupSchema.index({ members: 1 });

module.exports = mongoose.model('Group', groupSchema);
