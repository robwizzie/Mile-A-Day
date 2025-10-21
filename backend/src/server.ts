import express, { Request, Response, NextFunction } from 'express';
import http from 'http';
import path from 'path';
import dotenv from 'dotenv';
import userRoutes from './routes/usersRoutes.js';
import friendRoutes from './routes/friendshipsRoutes.js';
import authRoutes from './routes/authRoutes.js';
import devRoutes from './routes/devRoutes.js';
import { authenticateToken } from './middleware/auth.js';
import { webcrypto } from 'node:crypto';

(globalThis as any).crypto ??= webcrypto;

dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT ?? '3000');

app.use(express.json());

app.get('/status', (req, res) => {
	res.send('healthy');
});

app.get('/test-signin.html', (req, res) => {
	res.sendFile(path.join(process.cwd(), 'test-signin.html'));
});

app.use('/auth', authRoutes);
app.use('/dev', devRoutes);

app.use(authenticateToken);
app.use('/users', userRoutes);
app.use('/friends', friendRoutes);

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
});
