import express, { Request, Response, NextFunction } from 'express';
import http from 'http';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import userRoutes from './routes/usersRoutes.js';
import friendRoutes from './routes/friendshipsRoutes.js';
import authRoutes from './routes/authRoutes.js';
import devRoutes from './routes/devRoutes.js';
import workoutRoutes from './routes/workoutRoutes.js';
import competitionRoutes from './routes/competitionRoutes.js';
import deviceRoutes from './routes/deviceRoutes.js';
import { authenticateToken } from './middleware/auth.js';
import { startCompetitionCron } from './cron/competitionCron.js';
import { startNotificationCron } from './cron/notificationCron.js';
import { PostgresService } from './services/DbService.js';
import { webcrypto } from 'node:crypto';

(globalThis as any).crypto ??= webcrypto;

dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT ?? '3000');

app.use(express.json());

// Ensure uploads directory exists
const uploadsDir = path.join(process.cwd(), 'uploads', 'profile-images');
fs.mkdirSync(uploadsDir, { recursive: true });

app.use('/uploads', express.static(path.join(process.cwd(), 'uploads')));

app.get('/status', (req, res) => {
	res.send('healthy');
});

app.get('/test-signin.html', (req, res) => {
	res.sendFile(path.join(process.cwd(), 'test-signin.html'));
});

// Public endpoint: get profile image URL by username
app.get('/public/profile-image/:username', (req, res, next) => {
	res.setHeader('Access-Control-Allow-Origin', '*');
	next();
}, async (req, res) => {
	const db = PostgresService.getInstance();
	const results = await db.query(
		'SELECT profile_image_url FROM users WHERE username = $1',
		[req.params.username]
	);
	if (!results.length || !results[0].profile_image_url) {
		return res.status(404).json({ error: 'Not found' });
	}
	res.json({ profile_image_url: results[0].profile_image_url });
});

app.use('/auth', authRoutes);
app.use('/dev', devRoutes);

app.use(authenticateToken);
app.use('/users', userRoutes);
app.use('/friends', friendRoutes);
app.use('/workouts', workoutRoutes);
app.use('/competitions', competitionRoutes);
app.use('/devices', deviceRoutes);

app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
	console.error('Error:', err.message);

	res.status(500).json({
		error: 'Internal Server Error',
		message: err.message
	});
});

const server = http.createServer(app);
server.listen(PORT, '0.0.0.0', () => {
	console.log(`Server running on port ${PORT}`);
	startCompetitionCron();
	startNotificationCron();
});
