import { Router } from 'express';
import { createUser, getUser } from '../controllers/users/index.js';
import searchUsers from '../controllers/users/searchUsers.js';

const router = Router();

router.post('/create', createUser);
router.get('/search', searchUsers);
router.get('/:id', getUser);

export default router;
