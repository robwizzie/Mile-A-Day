import { Router } from 'express';
import { createUser, deleteUser, getUser, searchUsers, updateUser } from '../controllers/users/index.js';

const router = Router();

router.post('/create', createUser);
router.get('/search', searchUsers);
router.get('/:id', getUser);
router.delete('/:id', deleteUser);
router.patch('/:id', updateUser);

export default router;
