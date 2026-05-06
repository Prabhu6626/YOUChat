const express = require('express');
const { v4: uuidv4 } = require('uuid');
const Group = require('../models/Group');
const User = require('../models/User');
const authMiddleware = require('../middleware/auth');
const logger = require('../utils/logger');

const router = express.Router();

/**
 * POST /api/groups
 * Create a new group.
 * Body: { name: string, members: string[] }
 * The creator is automatically added as a member.
 */
router.post('/', authMiddleware, async (req, res) => {
  try {
    const { name, members } = req.body;

    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Group name is required.' });
    }

    if (name.trim().length > 50) {
      return res.status(400).json({ error: 'Group name must be 50 characters or less.' });
    }

    if (!members || !Array.isArray(members) || members.length === 0) {
      return res.status(400).json({ error: 'At least one other member is required.' });
    }

    // Validate all member userIds exist
    const allMembers = [...new Set([req.userId, ...members])];
    const existingUsers = await User.find({ userId: { $in: allMembers } }).select('userId');
    const existingIds = existingUsers.map((u) => u.userId);

    const invalid = allMembers.filter((m) => !existingIds.includes(m));
    if (invalid.length > 0) {
      return res.status(400).json({ error: `Users not found: ${invalid.join(', ')}` });
    }

    const groupId = uuidv4();
    const group = new Group({
      groupId,
      name: name.trim(),
      creatorId: req.userId,
      members: allMembers,
      admins: [req.userId],
    });

    await group.save();

    logger.info(`Group created: ${groupId} "${name}" by ${req.userId} (${allMembers.length} members)`);

    res.status(201).json({
      groupId: group.groupId,
      name: group.name,
      creatorId: group.creatorId,
      members: group.members,
      admins: group.admins,
      groupPictureUrl: group.groupPictureUrl,
      settings: group.settings,
      createdAt: group.createdAt,
    });
  } catch (error) {
    logger.error('Group creation error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * GET /api/groups
 * List all groups the authenticated user belongs to.
 */
router.get('/', authMiddleware, async (req, res) => {
  try {
    const groups = await Group.find({ members: req.userId }).select(
      'groupId name creatorId members admins groupPictureUrl settings createdAt'
    );

    res.json(groups);
  } catch (error) {
    logger.error('Group list error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * GET /api/groups/:groupId
 * Get a single group's details.
 */
router.get('/:groupId', authMiddleware, async (req, res) => {
  try {
    const group = await Group.findOne({ groupId: req.params.groupId });
    if (!group) {
      return res.status(404).json({ error: 'Group not found.' });
    }

    if (!group.members.includes(req.userId)) {
      return res.status(403).json({ error: 'You are not a member of this group.' });
    }

    res.json({
      groupId: group.groupId,
      name: group.name,
      creatorId: group.creatorId,
      members: group.members,
      admins: group.admins,
      groupPictureUrl: group.groupPictureUrl,
      settings: group.settings,
      createdAt: group.createdAt,
    });
  } catch (error) {
    logger.error('Group fetch error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * PUT /api/groups/:groupId/members
 * Add members to a group. Any member can add.
 * Body: { members: string[] }
 */
router.put('/:groupId/members', authMiddleware, async (req, res) => {
  try {
    const { members } = req.body;
    if (!members || !Array.isArray(members) || members.length === 0) {
      return res.status(400).json({ error: 'Members array is required.' });
    }

    const group = await Group.findOne({ groupId: req.params.groupId });
    if (!group) {
      return res.status(404).json({ error: 'Group not found.' });
    }

    if (!group.members.includes(req.userId)) {
      return res.status(403).json({ error: 'You are not a member of this group.' });
    }

    // Validate new members exist
    const existingUsers = await User.find({ userId: { $in: members } }).select('userId');
    const existingIds = existingUsers.map((u) => u.userId);
    const invalid = members.filter((m) => !existingIds.includes(m));
    if (invalid.length > 0) {
      return res.status(400).json({ error: `Users not found: ${invalid.join(', ')}` });
    }

    // Add new members (deduplicate)
    const newMembers = members.filter((m) => !group.members.includes(m));
    if (newMembers.length === 0) {
      return res.json({ message: 'All users are already members.', members: group.members });
    }

    group.members.push(...newMembers);
    await group.save();

    logger.info(`Members added to ${group.groupId}: ${newMembers.join(', ')}`);

    res.json({ message: 'Members added.', members: group.members });
  } catch (error) {
    logger.error('Add members error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

/**
 * DELETE /api/groups/:groupId/members/:userId
 * Remove a member. Any member can remove themselves, creator can remove anyone.
 */
router.delete('/:groupId/members/:userId', authMiddleware, async (req, res) => {
  try {
    const group = await Group.findOne({ groupId: req.params.groupId });
    if (!group) {
      return res.status(404).json({ error: 'Group not found.' });
    }

    if (!group.members.includes(req.userId)) {
      return res.status(403).json({ error: 'You are not a member of this group.' });
    }

    const targetUserId = req.params.userId;

    // Can only remove self or be the creator
    if (targetUserId !== req.userId && group.creatorId !== req.userId) {
      return res.status(403).json({ error: 'Only the group creator can remove other members.' });
    }

    group.members = group.members.filter((m) => m !== targetUserId);
    await group.save();

    logger.info(`Member removed from ${group.groupId}: ${targetUserId}`);

    res.json({ message: 'Member removed.', members: group.members });
  } catch (error) {
    logger.error('Remove member error:', error.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

module.exports = router;
