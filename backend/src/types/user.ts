export type User = {
	user_id: string;
	username: string;
	email: string;
	first_name?: string;
	last_name?: string;
};

export type Friendship = {
	user_id: string;
	friend_id: string;
	status: 'pending' | 'ignored' | 'accepted';
};
