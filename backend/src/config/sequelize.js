import 'dotenv/config';
import fs from 'fs';

// Helper function to read from secret files
const readSecretFile = (filePath) => {
  try {
    return fs.readFileSync(filePath, 'utf8').trim();
  } catch (error) {
    return null;
  }
};

const DB_HOST = process.env.DB_HOST;
const DB_PORT = process.env.DB_PORT || 5432;

const DB_NAME = process.env.DB_NAME_FILE
  ? readSecretFile(process.env.DB_NAME_FILE)
  : process.env.DB_NAME;

const DB_USER = process.env.DB_USER_FILE
  ? readSecretFile(process.env.DB_USER_FILE)
  : process.env.DB_USER;

const DB_PASSWORD = process.env.DB_PASSWORD_FILE
  ? readSecretFile(process.env.DB_PASSWORD_FILE)
  : process.env.DB_PASSWORD;

const defaultConfig = {
  dialect: 'postgres',
  timezone: '+03:00',
  username: DB_USER,
  password: DB_PASSWORD,
  database: DB_NAME,
  host: DB_HOST,
  port: Number(DB_PORT),
  define: {
    paranoid: true,
  },
};

export const development = {
  ...defaultConfig,
};

export const test = {
  ...defaultConfig,
  logging: false,
};

export const production = {
  ...defaultConfig,
  logging: false,
};
