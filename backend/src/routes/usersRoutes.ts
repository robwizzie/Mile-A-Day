import { Router } from 'express';
import { deleteUser, getUser, searchUsers, updateUser } from '../controllers/usersController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.get('/search', searchUsers);
router.get('/:userId', getUser);
router.delete('/:userId', requireSelfAccess('userId'), deleteUser);
router.patch('/:userId', requireSelfAccess('userId'), updateUser);

export default router;
