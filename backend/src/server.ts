import express from 'express';
import http from 'http';
import userRoutes from './routes/users.js';

const app = express();
const PORT = parseInt(process.env.PORT ?? '3000');

app.use(express.json());
app.use('/users', userRoutes);

app.get('/status', (req, res) => {
	res.send('healthy');
});

const server = http.createServer(app);
server.listen(PORT, '0.0.0.0', () => {
	console.log(`Server running on port ${PORT}`);
});
