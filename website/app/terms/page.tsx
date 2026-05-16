import type { Metadata } from 'next';
import { LegalPage, Section } from '@/components/legal-page';

export const metadata: Metadata = {
	title: 'Terms of Use - Mile A Day',
	description: 'The terms and conditions for using the Mile A Day app.'
};

export default function TermsPage() {
	return (
		<LegalPage title="TERMS OF USE" lastUpdated="May 16, 2026">
			<Section heading="Acceptance of Terms">
				<p>
					These Terms of Use (&ldquo;Terms&rdquo;) govern your use of the Mile A Day app and related services
					(&ldquo;the app&rdquo;). By creating an account or using the app, you agree to these Terms. If you do not
					agree, please do not use the app.
				</p>
			</Section>

			<Section heading="Eligibility">
				<p>
					You must be at least 13 years old to use Mile A Day. By using the app, you confirm that you meet this
					requirement and that the information you provide is accurate.
				</p>
			</Section>

			<Section heading="Your Account">
				<p>
					You are responsible for activity that occurs under your account and for keeping your sign-in credentials
					secure. You agree to provide accurate information and to notify us of any unauthorized use of your account.
				</p>
			</Section>

			<Section heading="Health and Fitness Disclaimer">
				<p>
					Mile A Day is a fitness motivation and tracking app. It is not a medical device and does not provide medical
					advice. The app encourages daily physical activity, but you are solely responsible for exercising safely.
					Consult a physician before beginning any new exercise routine. Do not ignore medical advice or delay seeking
					it because of anything in the app.
				</p>
				<p>
					Fitness data shown in the app, including distances, streaks, and records, is derived from Apple HealthKit and
					your device&rsquo;s sensors and may not always be accurate.
				</p>
			</Section>

			<Section heading="Acceptable Use">
				<p>You agree not to:</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>Submit false or manipulated fitness data, or otherwise cheat in streaks or competitions.</li>
					<li>Harass, abuse, or harm other users.</li>
					<li>Attempt to access accounts, data, or systems that do not belong to you.</li>
					<li>Interfere with, disrupt, or reverse engineer the app or its infrastructure.</li>
					<li>Use the app for any unlawful purpose or in violation of these Terms.</li>
				</ul>
				<p>We may suspend or terminate accounts that violate these Terms or that harm the experience of other users.</p>
			</Section>

			<Section heading="User Content">
				<p>
					You retain ownership of content you provide, such as your profile photo and username. By submitting content,
					you grant us a limited license to display it within the app as needed to operate features like profiles,
					friends, and competitions. You are responsible for ensuring you have the right to share any content you
					upload.
				</p>
			</Section>

			<Section heading="Intellectual Property">
				<p>
					The Mile A Day app, including its name, logo, design, and software, is owned by us and protected by applicable
					intellectual property laws. These Terms do not grant you any rights to our trademarks or branding.
				</p>
			</Section>

			<Section heading="Termination">
				<p>
					You may stop using the app and delete your account at any time from within the app. We may suspend or
					terminate your access if you violate these Terms or if we discontinue the service.
				</p>
			</Section>

			<Section heading="Disclaimer of Warranties">
				<p>
					The app is provided &ldquo;as is&rdquo; and &ldquo;as available&rdquo; without warranties of any kind, whether
					express or implied. We do not guarantee that the app will be uninterrupted, error-free, or that data will
					always be accurate.
				</p>
			</Section>

			<Section heading="Limitation of Liability">
				<p>
					To the maximum extent permitted by law, Mile A Day and its creators will not be liable for any indirect,
					incidental, or consequential damages, or for any loss arising from your use of, or inability to use, the app,
					including any injury related to physical activity.
				</p>
			</Section>

			<Section heading="Changes to These Terms">
				<p>
					We may update these Terms from time to time. When we do, we will revise the &ldquo;Last updated&rdquo; date
					above. Your continued use of the app after changes take effect constitutes acceptance of the updated Terms.
				</p>
			</Section>

			<Section heading="Contact Us">
				<p>
					If you have questions about these Terms, contact us at{' '}
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
