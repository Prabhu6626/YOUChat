const express = require('express');
const bcrypt = require('bcrypt');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const User = require('../models/User');
const authMiddleware = require('../middleware/auth');
const logger = require('../utils/logger');

const router = express.Router();

// Configure multer for profile picture uploads
const uploadDir = process.env.UPLOAD_DIR || './uploads';
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `${req.userId}_${Date.now()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB max
});

/**
 * GET /api/users/search?userId=<exact>
 * Search for a user by exact userId match.
 */
router.get('/search', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.query;

    if (!userId) {
      return res.status(400).json({ error: 'userId query parameter is required.' });
    }

    // Exact match only — no fuzzy, no partial
    const user = await User.findOne({ userId }).select('userId bio profilePictureUrl');
    if (!user) {
      return res.status(404).json({ error: 'User not found.' });
    }

    // Don't return own profile in search
    if (user.userId === req.userId) {
      return res.status(400).json({ error: 'Cannot search for yourself.' });
    }

    res.json({
      userId: user.userId,
      bio: user.bio,
      profilePictureUrl: user.profilePictureUrl,
    });
  } catch (error) {
    logger.error('Search error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * GET /api/users/me
 * Get own profile.
 */
router.get('/me', authMiddleware, async (req, res) => {
  try {
    const user = await User.findOne({ userId: req.userId }).select(
      'userId bio profilePictureUrl'
    );
    if (!user) {
      return res.status(404).json({ error: 'User not found.' });
    }

    res.json({
      userId: user.userId,
      bio: user.bio,
      profilePictureUrl: user.profilePictureUrl,
    });
  } catch (error) {
    logger.error('Profile fetch error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * PUT /api/users/profile
 * Update bio, profile picture, or change passcode.
 */
router.put('/profile', authMiddleware, upload.single('profilePicture'), async (req, res) => {
  try {
    const updates = {};

    // Update bio
    if (req.body.bio !== undefined) {
      if (req.body.bio.length > 200) {
        return res.status(400).json({ error: 'Bio must be 200 characters or less.' });
      }
      updates.bio = req.body.bio;
    }

    // Update profile picture
    if (req.file) {
      updates.profilePictureUrl = `/uploads/${req.file.filename}`;
    }

    // Change passcode
    if (req.body.newPasscode) {
      if (!req.body.oldPasscode) {
        return res.status(400).json({ error: 'Old passcode is required to change passcode.' });
      }

      const user = await User.findOne({ userId: req.userId });
      const isMatch = await bcrypt.compare(req.body.oldPasscode, user.hashedPasscode);
      if (!isMatch) {
        return res.status(401).json({ error: 'Old passcode is incorrect.' });
      }

      if (req.body.newPasscode.length < 6) {
        return res.status(400).json({ error: 'New passcode must be at least 6 characters.' });
      }

      updates.hashedPasscode = await bcrypt.hash(req.body.newPasscode, 12);
    }

    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ error: 'No updates provided.' });
    }

    await User.updateOne({ userId: req.userId }, { $set: updates });

    logger.info(`Profile updated: ${req.userId}`);

    res.json({ message: 'Profile updated successfully.' });
  } catch (error) {
    logger.error('Profile update error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * POST /api/users/fcm-token
 * Store the FCM token for a user.
 */
router.post('/fcm-token', authMiddleware, async (req, res) => {
  try {
    const { token } = req.body;
    if (!token) {
      return res.status(400).json({ error: 'Token is required.' });
    }

    await User.updateOne({ userId: req.userId }, { $set: { fcmToken: token } });
    logger.info(`FCM token updated for user: ${req.userId}`);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error updating FCM token:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

module.exports = router;
