const express = require('express');
const User = require('../models/User');
const authMiddleware = require('../middleware/auth');
const logger = require('../utils/logger');

const router = express.Router();

/**
 * POST /api/keys/bundle
 * Upload Signal Protocol key bundle (identity key, signed pre-key, one-time pre-keys).
 */
router.post('/bundle', authMiddleware, async (req, res) => {
  try {
    const { identityPublicKey, registrationId, signedPreKey, preKeys } = req.body;

    if (!identityPublicKey || registrationId === undefined || !signedPreKey || !preKeys) {
      return res.status(400).json({ error: 'Complete key bundle is required.' });
    }

    if (signedPreKey.keyId === undefined || !signedPreKey.publicKey || !signedPreKey.signature) {
      return res.status(400).json({ error: 'Signed pre-key must include keyId, publicKey, and signature.' });
    }

    if (!Array.isArray(preKeys) || preKeys.length === 0) {
      return res.status(400).json({ error: 'At least one pre-key is required.' });
    }

    await User.updateOne(
      { userId: req.userId },
      {
        $set: {
          identityPublicKey,
          registrationId,
          signedPreKey,
          preKeys,
        },
      }
    );

    logger.info(`Key bundle uploaded: ${req.userId} (${preKeys.length} pre-keys)`);

    res.json({ message: 'Key bundle uploaded successfully.' });
  } catch (error) {
    logger.error('Key bundle upload error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * GET /api/keys/bundle/:userId
 * Fetch a user's key bundle for session establishment.
 * Consumes (removes) one one-time pre-key.
 */
router.get('/bundle/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;

    const user = await User.findOne({ userId }).select(
      'userId registrationId identityPublicKey signedPreKey preKeys'
    );

    if (!user) {
      return res.status(404).json({ error: 'User not found.' });
    }

    if (!user.identityPublicKey || !user.signedPreKey) {
      return res.status(404).json({ error: 'User has not uploaded encryption keys yet.' });
    }

    // Consume one pre-key (remove it from the array)
    let oneTimePreKey = null;
    if (user.preKeys && user.preKeys.length > 0) {
      oneTimePreKey = user.preKeys[0];
      await User.updateOne(
        { userId },
        { $pull: { preKeys: { keyId: oneTimePreKey.keyId } } }
      );
    }

    res.json({
      userId: user.userId,
      registrationId: user.registrationId,
      identityPublicKey: user.identityPublicKey,
      signedPreKey: user.signedPreKey,
      preKey: oneTimePreKey, // May be null if all consumed
    });
  } catch (error) {
    logger.error('Key bundle fetch error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * GET /api/keys/count
 * Get remaining pre-key count (so client knows when to upload more).
 */
router.get('/count', authMiddleware, async (req, res) => {
  try {
    const user = await User.findOne({ userId: req.userId }).select('preKeys');
    const count = user?.preKeys?.length || 0;
    res.json({ preKeyCount: count });
  } catch (error) {
    logger.error('Pre-key count error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

module.exports = router;
