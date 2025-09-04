import { Request, Response } from 'express';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';
import { getUser as dbGetUser, createUser as dbCreateUser } from '../services/userService.js';
import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';

export async function signIn(req: Request, res: Response) {
	if (!hasRequiredKeys(['user_id', 'identity_token', 'authorization_code'], req, res)) return;

	const identityToken = req.body.identity_token as string;
	const email = req.body.email as string;

	const expectedAudience = process.env.APPLE_CLIENT_ID;
	const appJwtSecret = process.env.APP_JWT_SECRET;

	try {
		const APPLE_ISS = 'https://appleid.apple.com';
		const jwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
		const { payload } = await jwtVerify(identityToken, jwks, {
			issuer: APPLE_ISS,
			audience: expectedAudience
		});

		const appleSub = payload.sub as string;
		const emailFromToken = (payload.email as string | undefined) ?? email;

		let user = await dbGetUser({ email: emailFromToken });

		if (!user) {
			user = await dbCreateUser({ email: emailFromToken, apple_sub: appleSub });
		}

		const token = await new SignJWT({ provider: 'apple' })
			.setProtectedHeader({ alg: 'HS256' })
			.setSubject(user.user_id)
			.setIssuedAt()
			.setExpirationTime('30d')
			.sign(new TextEncoder().encode(appJwtSecret));

		return res.json({ user, token });
	} catch (err) {
		console.error('Apple sign-in failed', err);
		return res.status(401).json({ error: 'Invalid Apple identity token' });
	}
}
