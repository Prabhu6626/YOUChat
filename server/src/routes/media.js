const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const authMiddleware = require('../middleware/auth');
const logger = require('../utils/logger');

const router = express.Router();

// Media uploads directory
const uploadDir = process.env.UPLOAD_DIR || './uploads';
const mediaDir = path.join(uploadDir, 'media');
if (!fs.existsSync(mediaDir)) {
  fs.mkdirSync(mediaDir, { recursive: true });
}

// Multer config for media (photos + videos)
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, mediaDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    const uniqueName = `${req.userId}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}${ext}`;
    cb(null, uniqueName);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024 }, // 50MB max
});

/**
 * POST /api/media/upload
 * Upload a photo or video. Returns the URL path.
 */
router.post('/upload', authMiddleware, upload.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded.' });
    }

    const mediaUrl = `/uploads/media/${req.file.filename}`;
    let mediaType = 'file';
    const mimetype = (req.file.mimetype || '').toLowerCase();
    const originalName = (req.file.originalname || '').toLowerCase();
    
    if (mimetype.startsWith('video/') || originalName.match(/\\.(mp4|mov|avi|wmv|mkv)$/i)) {
      mediaType = 'video';
    } else if (mimetype.startsWith('image/') || originalName.match(/\\.(jpg|jpeg|png|gif|webp|bmp)$/i)) {
      mediaType = 'image';
    }

    logger.info(`Media uploaded by ${req.userId}: ${mediaType} (${(req.file.size / 1024).toFixed(1)}KB)`);

    res.status(201).json({
      mediaUrl,
      mediaType,
      filename: req.file.filename,
      originalName: req.file.originalname,
      size: req.file.size,
    });
  } catch (error) {
    logger.error('Media upload error:', error.message);
    res.status(500).json({ error: 'Upload failed.' });
  }
});

// Handle multer errors
router.use((err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({ error: 'File too large. Max 50MB.' });
    }
    return res.status(400).json({ error: err.message });
  }
  if (err) {
    return res.status(400).json({ error: err.message });
  }
  next();
});

module.exports = router;
