/**
 * Logger utility - No-op in production to prevent any data leaks.
 * Only logs in development mode.
 * NEVER logs message content, user data, or tokens.
 */

const isDev = process.env.NODE_ENV === 'development';

const logger = {
  info: (...args) => {
    if (isDev) console.log('[INFO]', new Date().toISOString(), ...args);
  },
  warn: (...args) => {
    if (isDev) console.warn('[WARN]', new Date().toISOString(), ...args);
  },
  error: (...args) => {
    // Errors are logged even in production for debugging server issues
    // But NEVER log message content or user data
    console.error('[ERROR]', new Date().toISOString(), ...args);
  },
  debug: (...args) => {
    if (isDev) console.log('[DEBUG]', new Date().toISOString(), ...args);
  },
};

module.exports = logger;
