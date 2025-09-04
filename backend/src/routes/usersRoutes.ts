import { Router } from 'express';
import { deleteUser, getUser, searchUsers, updateUser } from '../controllers/usersController.js';

const router = Router();

router.get('/search', searchUsers);
router.get('/:userId', getUser);
router.delete('/:userId', deleteUser);
router.patch('/:userId', updateUser);

export default router;
