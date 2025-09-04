import express, { Request, Response, NextFunction } from 'express';
import http from 'http';
import dotenv from 'dotenv';
import userRoutes from './routes/usersRoutes.js';
import friendRoutes from './routes/friendshipsRoutes.js';
import authRoutes from './routes/authRoutes.js';

import { webcrypto } from 'node:crypto';
(globalThis as any).crypto ??= webcrypto;

dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT ?? '3000');

app.use(express.json());
app.use('/users', userRoutes);
app.use('/friends', friendRoutes);
app.use('/auth', authRoutes);

app.get('/status', (req, res) => {
	res.send('healthy');
});

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
