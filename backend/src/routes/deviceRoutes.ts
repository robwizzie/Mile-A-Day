import { Router } from 'express';
import { registerDevice, unregisterDevice } from '../controllers/deviceController.js';

const router = Router();

router.post('/register', registerDevice);
router.delete('/unregister', unregisterDevice);

export default router;
