require('dotenv').config();

const express = require('express');
const http = require('http');
const cors = require('cors');
const path = require('path');
const connectDB = require('./config/db');
const { initializeFirebase } = require('./config/firebase');
const WebSocketHandler = require('./websocket/handler');
const logger = require('./utils/logger');

// Route imports
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/user');
const keyRoutes = require('./routes/keys');
const groupRoutes = require('./routes/group');
const groupSettingsRoutes = require('./routes/groupSettings');
const mediaRoutes = require('./routes/media');
const messageRoutes = require('./routes/messages');

const app = express();
const server = http.createServer(app);

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Serve uploaded files (profile pictures + media)
app.use('/uploads', express.static(path.join(__dirname, '..', process.env.UPLOAD_DIR || 'uploads')));

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/keys', keyRoutes);
app.use('/api/groups', groupRoutes);
app.use('/api/groups', groupSettingsRoutes); // Mount settings routes on the same /api/groups prefix
app.use('/api/media', mediaRoutes);
app.use('/api/messages', messageRoutes);

// Health check
app.get('/api/health', (req, res) => {
  const wsStats = wsHandler ? wsHandler.getStats() : {};
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    ...wsStats,
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found.' });
});

// Error handler — no stack traces in production
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err.message);
  res.status(500).json({ error: 'Internal server error.' });
});

// Initialize
let wsHandler;

const start = async () => {
  // Initialize Firebase Admin
  initializeFirebase();

  // Connect to MongoDB
  await connectDB();

  // Start HTTP + WebSocket server on same port
  const PORT = process.env.PORT || 3000;

  server.listen(PORT, () => {
    logger.info(`YOUChat server running on port ${PORT}`);
    logger.info(`WebSocket server running on ws://localhost:${PORT}`);
    logger.info(`Environment: ${process.env.NODE_ENV}`);
  });

  // Initialize WebSocket on the same HTTP server
  wsHandler = new WebSocketHandler(server);
};

start().catch((err) => {
  logger.error('Server startup failed:', err.message);
  process.exit(1);
});
