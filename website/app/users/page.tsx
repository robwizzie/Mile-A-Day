import type { Metadata } from 'next';
import { LiveCounter } from './live-counter';

export const metadata: Metadata = {
	title: 'Users — Mile A Day',
	description: 'Live Mile A Day user counter.',
	robots: { index: false, follow: false }
};

export default function UsersPage() {
	return <LiveCounter />;
}
