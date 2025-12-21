import { SignJWT, jwtVerify } from 'jose';
import crypto from 'crypto';

const APP_JWT_SECRET = process.env.APP_JWT_SECRET!;
const ACCESS_TOKEN_EXPIRY = '15m';

export async function generateAccessToken(userId: string): Promise<string> {
	return await new SignJWT({ provider: 'apple' })
		.setProtectedHeader({ alg: 'HS256' })
		.setSubject(userId)
		.setIssuedAt()
		.setExpirationTime(ACCESS_TOKEN_EXPIRY)
		.sign(new TextEncoder().encode(APP_JWT_SECRET));
}

export function generateRefreshToken(): string {
	const randomBytes = crypto.randomBytes(32).toString('hex');
	const timestamp = Date.now().toString(36);
	return `rt_${randomBytes}_${timestamp}`;
}

export function hashRefreshToken(token: string): string {
	return crypto.createHash('sha256').update(token).digest('hex');
}

export async function verifyAccessToken(token: string): Promise<{ userId: string }> {
	const { payload } = await jwtVerify(token, new TextEncoder().encode(APP_JWT_SECRET));
	return { userId: payload.sub as string };
}
