import { Router } from 'express';
import { sendHype, getHypeStatus, getReceivedHypesController } from '../controllers/hypeController.js';

const router = Router();

router.post('/', sendHype);
router.get('/status', getHypeStatus);
router.get('/received', getReceivedHypesController);

export default router;
