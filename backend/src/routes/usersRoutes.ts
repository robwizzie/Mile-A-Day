import { Router } from 'express';
import { deleteUser, getUser, searchUsers, searchUsersByPartialUsername, updateUser, updateUserUsername, checkUsername, updateUserBio, updateUserProfileImage } from '../controllers/usersController.js';

const router = Router();

router.get('/search', searchUsers);
router.get('/search-partial', searchUsersByPartialUsername);
router.get('/check-username', checkUsername);
router.get('/:userId', getUser);
router.delete('/:userId', deleteUser);
router.patch('/:userId', updateUser);
router.patch('/:userId/username', updateUserUsername);
router.patch('/:userId/bio', updateUserBio);
router.patch('/:userId/profile-image', updateUserProfileImage);

export default router;
