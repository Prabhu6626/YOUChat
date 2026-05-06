const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const logger = require('../utils/logger');

const router = express.Router();

const BCRYPT_ROUNDS = 12;
const JWT_EXPIRY = '30d'; // Long-lived token, no session management

/**
 * POST /api/auth/register
 * Register a new user with userId and passcode only.
 */
router.post('/register', async (req, res) => {
  try {
    const { userId, passcode } = req.body;

    // Validation
    if (!userId || !passcode) {
      return res.status(400).json({ error: 'userId and passcode are required.' });
    }

    if (userId.length < 3 || userId.length > 30) {
      return res.status(400).json({ error: 'userId must be 3-30 characters.' });
    }

    if (!/^[a-zA-Z0-9_]+$/.test(userId)) {
      return res.status(400).json({ error: 'userId can only contain letters, numbers, and underscores.' });
    }

    if (passcode.length < 6) {
      return res.status(400).json({ error: 'Passcode must be at least 6 characters.' });
    }

    // Check if userId already exists
    const existingUser = await User.findOne({ userId });
    if (existingUser) {
      return res.status(409).json({ error: 'userId already taken.' });
    }

    // Hash passcode
    const hashedPasscode = await bcrypt.hash(passcode, BCRYPT_ROUNDS);

    // Create user
    const user = new User({
      userId,
      hashedPasscode,
    });
    await user.save();

    // Generate JWT
    const token = jwt.sign({ userId }, process.env.JWT_SECRET, {
      expiresIn: JWT_EXPIRY,
    });

    logger.info(`User registered: ${userId}`);

    res.status(201).json({
      message: 'Registration successful.',
      token,
      userId,
    });
  } catch (error) {
    logger.error('Registration error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * POST /api/auth/login
 * Login with userId and passcode.
 */
router.post('/login', async (req, res) => {
  try {
    const { userId, passcode } = req.body;

    if (!userId || !passcode) {
      return res.status(400).json({ error: 'userId and passcode are required.' });
    }

    // Find user
    const user = await User.findOne({ userId });
    if (!user) {
      return res.status(401).json({ error: 'Invalid userId or passcode.' });
    }

    // Verify passcode
    const isMatch = await bcrypt.compare(passcode, user.hashedPasscode);
    if (!isMatch) {
      return res.status(401).json({ error: 'Invalid userId or passcode.' });
    }

    // Generate JWT
    const token = jwt.sign({ userId }, process.env.JWT_SECRET, {
      expiresIn: JWT_EXPIRY,
    });

    logger.info(`User logged in: ${userId}`);

    res.json({
      message: 'Login successful.',
      token,
      userId,
    });
  } catch (error) {
    logger.error('Login error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

module.exports = router;
