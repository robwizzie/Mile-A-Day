export interface RefreshToken {
	token_id: string;
	user_id: string;
	token_hash: string;
	token_family_id: string;
	created_at: Date;
	last_used_at: Date;
	expires_at: Date | null;
	revoked_at: Date | null;
	revoked_reason: string | null;
	user_agent?: string;
	ip_address?: string;
	device_info?: any;
}

export interface TokenPair {
	accessToken: string;
	refreshToken: string;
}

export interface RefreshTokenMetadata {
	userAgent?: string;
	ipAddress?: string;
	deviceInfo?: any;
}
