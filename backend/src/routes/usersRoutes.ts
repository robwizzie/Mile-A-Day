import { Router } from 'express';
import {
	deleteUser,
	getUser,
	searchUsers,
	updateUser,
	updateUserUsername,
	checkUsername,
	updateUserBio,
	updateUserProfileImage
} from '../controllers/usersController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.get('/search', searchUsers);
router.get('/check-username', checkUsername);
router.get('/:userId', getUser);
router.delete('/:userId', requireSelfAccess('userId'), deleteUser);
router.patch('/:userId', requireSelfAccess('userId'), updateUser);
router.patch('/:userId/username', requireSelfAccess('userId'), updateUserUsername);
router.patch('/:userId/bio', requireSelfAccess('userId'), updateUserBio);
router.patch('/:userId/profile-image', requireSelfAccess('userId'), updateUserProfileImage);

export default router;
