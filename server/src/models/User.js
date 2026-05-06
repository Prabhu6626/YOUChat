const mongoose = require('mongoose');

/**
 * User Schema — Minimal data storage.
 * No timestamps, no session logs, no metadata.
 * Only stores: userId, hashedPasscode, bio, profilePictureUrl, and Signal Protocol public keys.
 */
const userSchema = new mongoose.Schema(
  {
    userId: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      minlength: 3,
      maxlength: 30,
      match: /^[a-zA-Z0-9_]+$/,
    },
    hashedPasscode: {
      type: String,
      required: true,
    },
    bio: {
      type: String,
      default: '',
      maxlength: 200,
    },
    profilePictureUrl: {
      type: String,
      default: '',
    },
    // Signal Protocol public keys for E2E encryption key exchange
    identityPublicKey: {
      type: String, // Base64 encoded
      default: null,
    },
    registrationId: {
      type: Number,
      default: null,
    },
    signedPreKey: {
      keyId: { type: Number },
      publicKey: { type: String }, // Base64
      signature: { type: String }, // Base64
    },
    preKeys: [
      {
        keyId: { type: Number },
        publicKey: { type: String }, // Base64
      },
    ],
    fcmToken: {
      type: String,
      default: null,
    },
  },
  {
    timestamps: false, // No timestamps — privacy
    versionKey: false, // No __v field
  }
);

module.exports = mongoose.model('User', userSchema);
