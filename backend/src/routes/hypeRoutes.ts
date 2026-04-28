import { Router } from 'express';
import { sendHype, getHypeStatus } from '../controllers/hypeController.js';

const router = Router();

router.post('/', sendHype);
router.get('/status', getHypeStatus);

export default router;
