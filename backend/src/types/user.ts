export type User = {
	user_id: string;
	username: string;
	email: string;
	first_name?: string;
	last_name?: string;
	apple_id?: string; // Apple's unique user identifier
	auth_provider?: 'apple' | 'google' | 'guest';
};

export type Friendship = {
	user_id: string;
	friend_id: string;
	status: 'pending' | 'ignored' | 'accepted';
};

export type AppleAuthRequest = {
	user_id: string; // Apple's user ID
	identity_token: string;
	authorization_code: string;
	email?: string;
	full_name?: string;
};

export type AppleAuthResponse = {
	user: User;
	token: string; // Your app's JWT token
};
