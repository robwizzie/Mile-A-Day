import { Router } from 'express';
import { generateTestToken } from '../controllers/devController.js';

const router = Router();

router.post('/test-token', generateTestToken);

export default router;
