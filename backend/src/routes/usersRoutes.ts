import { Router } from 'express';
import multer from 'multer';
import {
	deleteUser,
	getUser,
	searchUsers,
	updateUser,
	updateUserUsername,
	checkUsername,
	updateUserBio,
	updateUserProfileImage,
	uploadProfileImage
} from '../controllers/usersController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const upload = multer({
	storage: multer.memoryStorage(),
	limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
	fileFilter: (_req, file, cb) => {
		if (['image/jpeg', 'image/png', 'image/webp'].includes(file.mimetype)) {
			cb(null, true);
		} else {
			cb(new Error('Only JPEG, PNG, and WebP images are allowed'));
		}
	}
});

const router = Router();

router.get('/search', searchUsers);
router.get('/check-username', checkUsername);
router.get('/:userId', getUser);
router.delete('/:userId', requireSelfAccess('userId'), deleteUser);
router.patch('/:userId', requireSelfAccess('userId'), updateUser);
router.patch('/:userId/username', requireSelfAccess('userId'), updateUserUsername);
router.patch('/:userId/bio', requireSelfAccess('userId'), updateUserBio);
router.patch('/:userId/profile-image', requireSelfAccess('userId'), updateUserProfileImage);
router.post('/:userId/profile-image/upload', requireSelfAccess('userId'), (req, res, next) => {
	upload.single('image')(req, res, (err) => {
		if (err) {
			return res.status(400).json({ error: 'File upload failed', message: err.message });
		}
		next();
	});
}, uploadProfileImage);

export default router;
