import type { Metadata } from 'next';
import { LegalPage, Section } from '@/components/legal-page';

export const metadata: Metadata = {
	title: 'Privacy Policy',
	description: 'How Mile A Day collects, uses, and protects your data.',
	alternates: { canonical: '/privacy' }
};

export default function PrivacyPage() {
	return (
		<LegalPage title="PRIVACY POLICY" lastUpdated="May 16, 2026">
			<Section heading="Overview">
				<p>
					Mile A Day (&ldquo;we,&rdquo; &ldquo;us,&rdquo; or &ldquo;the app&rdquo;) is a fitness app that helps you
					build a daily walking or running habit, track streaks, and compete with friends. This Privacy Policy explains
					what information we collect, how we use it, and the choices you have.
				</p>
				<p>By creating an account and using Mile A Day, you agree to the practices described in this policy.</p>
			</Section>

			<Section heading="Information We Collect">
				<p>
					<span className="font-semibold text-[#f5f5f5]">Account information.</span> When you sign in with Apple, we
					receive your name and an Apple-provided identifier. If you choose to hide your email, Apple provides a private
					relay address instead of your real email. We use this information to create and maintain your account.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Profile information.</span> Your chosen username, display name,
					and optional profile photo.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Health and fitness data.</span> With your explicit permission,
					the app reads workout and distance data from Apple HealthKit — including walks, runs, distance traveled, and
					workout dates — to calculate your daily mile, streaks, and personal records. This data is read from HealthKit
					on your device and synced to our servers to power streaks, leaderboards, and competitions.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Social activity.</span> Friend connections, competitions you
					join, and related activity needed to operate the social features of the app.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Usage and device data.</span> Basic technical information
					needed to operate the service, such as app version and authentication tokens.
				</p>
			</Section>

			<Section heading="How We Use Your Information">
				<ul className="list-disc space-y-2 pl-6">
					<li>To create your account and authenticate you when you sign in.</li>
					<li>To calculate and display your daily mile progress, streaks, and personal records.</li>
					<li>To power friends, leaderboards, and competitions.</li>
					<li>To send notifications you have enabled, such as streak reminders.</li>
					<li>To maintain, troubleshoot, and improve the app.</li>
				</ul>
			</Section>

			<Section heading="HealthKit Data">
				<p>
					Health data accessed through Apple HealthKit is used solely to provide the app&rsquo;s fitness tracking
					features. We do not use HealthKit data for advertising or marketing, and we do not sell it or share it with
					data brokers. You can review and revoke the app&rsquo;s HealthKit permissions at any time in the iOS Settings
					app under Privacy &amp; Security &rarr; Health.
				</p>
			</Section>

			<Section heading="How We Share Information">
				<p>We do not sell your personal information. We share information only in these limited cases:</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>
						<span className="font-semibold text-[#f5f5f5]">With other users.</span> Your username, profile photo,
						streak, and competition results are visible to friends and competition participants, as that is the core
						purpose of the app.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Service providers.</span> With infrastructure providers
						that host our servers and deliver the service, who are only permitted to use the data to provide those
						services.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Legal reasons.</span> When required by law or to protect
						the rights, safety, and security of our users and the service.
					</li>
				</ul>
			</Section>

			<Section heading="Data Retention and Deletion">
				<p>
					We retain your information for as long as your account is active. You can delete your account directly within
					the app, which removes your profile, fitness history, and social data from our servers. You may also request
					deletion by contacting us at the email below.
				</p>
			</Section>

			<Section heading="Your Choices">
				<ul className="list-disc space-y-2 pl-6">
					<li>Control HealthKit access in iOS Settings at any time.</li>
					<li>Enable or disable push notifications in iOS Settings or within the app.</li>
					<li>Delete your account and associated data from within the app.</li>
				</ul>
			</Section>

			<Section heading="Children&rsquo;s Privacy">
				<p>
					Mile A Day is not directed to children under 13, and we do not knowingly collect personal information from
					children under 13. If you believe a child has provided us with personal information, please contact us so we
					can remove it.
				</p>
			</Section>

			<Section heading="Changes to This Policy">
				<p>
					We may update this Privacy Policy from time to time. When we do, we will revise the &ldquo;Last updated&rdquo;
					date above. Significant changes may also be communicated within the app.
				</p>
			</Section>

			<Section heading="Contact Us">
				<p>
					If you have questions about this Privacy Policy or your data, contact us at{' '}
					<a
						href="mailto:support@mileaday.run"
						className="font-medium text-[#c72554] underline transition-colors hover:text-[#ff4d7d]"
					>
						support@mileaday.run
					</a>
					.
				</p>
			</Section>
		</LegalPage>
	);
}
