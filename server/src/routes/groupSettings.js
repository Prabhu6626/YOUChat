const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const Group = require('../models/Group');
const authMiddleware = require('../middleware/auth');
const logger = require('../utils/logger');

const router = express.Router({ mergeParams: true }); // Access :groupId from parent router inside `index.js` or directly if used here. Wait. Actually, we will mount it separately or as part of group.js.

// We will mount this in group.js or standalone. Let's make it exports a router that assumes /api/groups/:groupId/ is the prefix.

// Configure multer for group DP uploads
const uploadDir = process.env.UPLOAD_DIR || './uploads';
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `group_${req.params.groupId}_${Date.now()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB max
});

/**
 * PUT /api/groups/:groupId/dp
 * Upload/Update the group display picture.
 * Requires editGroupInfo permission.
 */
router.put('/dp', authMiddleware, upload.single('groupPicture'), async (req, res) => {
  try {
    const { groupId } = req.params;
    const group = await Group.findOne({ groupId });
    
    if (!group) return res.status(404).json({ error: 'Group not found.' });

    // Permissions check
    if (!group.members.includes(req.userId)) {
      return res.status(403).json({ error: 'Not a member of this group.' });
    }

    const isAdmin = group.admins && group.admins.includes(req.userId);
    const settings = group.settings || { editGroupInfo: 'all' };

    if (settings.editGroupInfo === 'admins' && !isAdmin) {
      return res.status(403).json({ error: 'Only admins can change group info.' });
    }

    if (!req.file) {
      return res.status(400).json({ error: 'No image provided.' });
    }

    group.groupPictureUrl = `/uploads/${req.file.filename}`;
    await group.save();

    logger.info(`Group DP updated for ${groupId} by ${req.userId}`);
    res.json({ message: 'Group picture updated.', groupPictureUrl: group.groupPictureUrl });
  } catch (error) {
    logger.error('Group DP update error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * PUT /api/groups/:groupId/settings
 * Update settings (editGroupInfo, sendMessages).
 * Requires Admin.
 */
router.put('/settings', authMiddleware, async (req, res) => {
  try {
    const { groupId } = req.params;
    const { editGroupInfo, sendMessages } = req.body;
    
    const group = await Group.findOne({ groupId });
    if (!group) return res.status(404).json({ error: 'Group not found.' });

    const isAdmin = group.admins && group.admins.includes(req.userId);
    if (!isAdmin) {
      return res.status(403).json({ error: 'Only admins can change group settings.' });
    }

    if (!group.settings) group.settings = {};
    
    if (editGroupInfo) {
      if (!['all', 'admins'].includes(editGroupInfo)) return res.status(400).json({ error: 'Invalid setting value' });
      group.settings.editGroupInfo = editGroupInfo;
    }
    
    if (sendMessages) {
      if (!['all', 'admins'].includes(sendMessages)) return res.status(400).json({ error: 'Invalid setting value' });
      group.settings.sendMessages = sendMessages;
    }

    await group.save();
    logger.info(`Group settings updated for ${groupId} by ${req.userId}`);
    res.json({ message: 'Group settings updated.', settings: group.settings });
  } catch (error) {
    logger.error('Group settings error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * PUT /api/groups/:groupId/admins
 * Add or remove admins.
 * Requires Admin. Note: Creator cannot be removed as admin.
 */
router.put('/admins', authMiddleware, async (req, res) => {
  try {
    const { groupId } = req.params;
    const { action, userId } = req.body; // action: 'add' or 'remove'
    
    if (!action || !userId) return res.status(400).json({ error: 'Missing action or userId.' });
    
    const group = await Group.findOne({ groupId });
    if (!group) return res.status(404).json({ error: 'Group not found.' });

    const isAdmin = group.admins && group.admins.includes(req.userId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can manage other admins.' });

    if (!group.members.includes(userId)) {
        return res.status(400).json({ error: 'User is not a member of the group.' });
    }

    if (!group.admins) group.admins = [group.creatorId];

    if (action === 'add') {
      if (!group.admins.includes(userId)) group.admins.push(userId);
    } else if (action === 'remove') {
      if (userId === group.creatorId) {
        return res.status(400).json({ error: 'Creator cannot be removed from admins.' });
      }
      group.admins = group.admins.filter(id => id !== userId);
    } else {
      return res.status(400).json({ error: 'Invalid action. Use add or remove.' });
    }

    await group.save();
    logger.info(`Group admin ${action} ${userId} in ${groupId} by ${req.userId}`);
    res.json({ message: 'Admins updated.', admins: group.admins });
  } catch (error) {
    logger.error('Group admins error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

module.exports = router;
