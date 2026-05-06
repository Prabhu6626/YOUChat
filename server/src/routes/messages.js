const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/auth');
const PendingMessage = require('../models/PendingMessage');
const logger = require('../utils/logger');

/**
 * GET /api/messages/pending
 * Fetch all pending (undelivered) messages for the authenticated user.
 * Called by the client on reconnect to sync missed messages.
 */
router.get('/pending', authMiddleware, async (req, res) => {
  try {
    const userId = req.userId;
    const messages = await PendingMessage.find({ to: userId })
      .sort({ createdAt: 1 })
      .lean();

    logger.info(`Fetched ${messages.length} pending messages for ${userId}`);
    res.json({ messages });
  } catch (error) {
    logger.error('Error fetching pending messages:', error.message);
    res.status(500).json({ error: 'Failed to fetch pending messages.' });
  }
});

/**
 * DELETE /api/messages/pending/:messageId
 * Acknowledge receipt of a pending message — deletes it from MongoDB.
 */
router.delete('/pending/:messageId', authMiddleware, async (req, res) => {
  try {
    const userId = req.userId;
    const { messageId } = req.params;

    await PendingMessage.deleteOne({ messageId, to: userId });
    res.json({ success: true });
  } catch (error) {
    logger.error('Error deleting pending message:', error.message);
    res.status(500).json({ error: 'Failed to delete pending message.' });
  }
});

/**
 * DELETE /api/messages/pending
 * Acknowledge receipt of ALL pending messages — bulk delete.
 */
router.delete('/pending', authMiddleware, async (req, res) => {
  try {
    const userId = req.userId;
    const result = await PendingMessage.deleteMany({ to: userId });
    logger.info(`Cleared ${result.deletedCount} pending messages for ${userId}`);
    res.json({ success: true, deleted: result.deletedCount });
  } catch (error) {
    logger.error('Error clearing pending messages:', error.message);
    res.status(500).json({ error: 'Failed to clear pending messages.' });
  }
});

module.exports = router;
