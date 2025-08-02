import { Router } from 'express';
import { createUser, deleteUser, getUser, searchUsers, updateUser } from '../controllers/usersController.js';

const router = Router();

router.post('/create', createUser);
router.get('/search', searchUsers);
router.get('/:userId', getUser);
router.delete('/:userId', deleteUser);
router.patch('/:userId', updateUser);

export default router;
