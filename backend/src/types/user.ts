export type User = {
	user_id: string;
	username: string;
	email: string;
	first_name?: string;
	last_name?: string;
	bio?: string;
	profile_image_url?: string;
	profile_banner_url?: string | null;
	profile_banner_style?: string | null;
	apple_id?: string;
	auth_provider?: 'apple' | 'google' | 'guest';
};

export type Friendship = {
	user_id: string;
	friend_id: string;
	status: 'pending' | 'ignored' | 'accepted';
};

export type AppleAuthRequest = {
	user_id: string;
	identity_token: string;
	authorization_code: string;
	email?: string;
	full_name?: string;
};

export type AppleAuthResponse = {
	user: User;
	token: string;
};
