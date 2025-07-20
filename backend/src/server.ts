import express from 'express';
import userRoutes from './routes/users.js';

const app = express();
const PORT = process.env.PORT ?? 3000;

app.use(express.json());
app.use('/users', userRoutes);

app.get('/', (req, res) => {
	res.send('hello world!');
});

app.listen(PORT, '0.0.0.0', () => {
	console.log(`🚀  Server running at http://localhost:${PORT}`);
});
