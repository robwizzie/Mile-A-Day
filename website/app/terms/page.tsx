import type { Metadata } from 'next';
import { LegalPage, Section } from '@/components/legal-page';

export const metadata: Metadata = {
	title: 'Terms of Use',
	description: 'The terms and conditions for using the Mile A Day app.',
	alternates: { canonical: '/terms' },
	// A page's openGraph/twitter REPLACE the root ones, so restate what a share
	// needs; the card image comes from this segment's opengraph-image.
	openGraph: {
		title: 'Terms of Use | Mile A Day',
		description: 'The terms and conditions for using the Mile A Day app.',
		url: '/terms',
		type: 'website',
		siteName: 'Mile A Day'
	},
	twitter: {
		card: 'summary_large_image',
		site: '@mileadayapp',
		title: 'Terms of Use | Mile A Day',
		description: 'The terms and conditions for using the Mile A Day app.'
	}
};

export default function TermsPage() {
	return (
		<LegalPage title="TERMS OF USE" lastUpdated="October 15, 2026">
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

			<Section heading="Mile A Day+">
				<p>
					Mile A Day+ is an optional membership. Logging your daily mile, streaks, friends, the feed and competitions
					remain free. Mile A Day+ adds extras such as faster-earning streak tokens, Mile A Day+-only looks for Flamey,
					and Family Sharing. The features included in Mile A Day+ are described in the app and may change over time;
					the free core of the app is not part of Mile A Day+.
				</p>
				<p>
					Mile A Day+ is sold only through Apple&rsquo;s App Store and is subject to Apple&rsquo;s Media Services Terms
					and Conditions as well as these Terms. All purchases are charged to the payment method on your Apple ID. We
					never receive or store your payment card details.
				</p>
			</Section>

			<Section heading="Subscriptions and Auto-Renewal">
				<p>
					Mile A Day+ is offered as a monthly or yearly auto-renewing subscription. Prices are shown in the app before
					you buy and may vary by country.
				</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>Payment is charged to your Apple ID when you confirm the purchase.</li>
					<li>
						Your subscription renews automatically at the same price and for the same period unless auto-renew is
						turned off at least 24 hours before the end of the current period. Your Apple ID is charged for the renewal
						within 24 hours before the current period ends.
					</li>
					<li>
						You can manage or cancel your subscription at any time in your Apple ID&rsquo;s Subscriptions settings
						(Settings &rsaquo; your name &rsaquo; Subscriptions on iPhone), or from Settings &rsaquo; Mile A Day+ in the
						app. Cancelling stops future renewals; you keep Mile A Day+ until the end of the period you have already
						paid for.
					</li>
					<li>
						If the price of your subscription changes, Apple will notify you in advance and, where required, ask for
						your consent before the new price applies.
					</li>
				</ul>
			</Section>

			<Section heading="Free Trials">
				<p>
					Some plans include a free trial for eligible new subscribers, as shown in the app. Eligibility is decided
					by Apple, generally once per Apple ID. Unless you cancel at least 24 hours before the trial ends, the
					subscription begins and your Apple ID is charged at the end of the trial. Any unused portion of a free
					trial is forfeited when you buy a subscription to the same plan.
				</p>
			</Section>

			<Section heading="Lifetime Purchase">
				<p>
					The Lifetime option is a one-time, non-renewing purchase that gives your account Mile A Day+ for as long as
					we offer Mile A Day+ in the app. It does not renew and you will not be charged again for it.
				</p>
			</Section>

			<Section heading="Founding Runners">
				<p>
					Accounts created before Mile A Day+ launched are Founding Runners and receive Mile A Day+ free of charge for
					as long as we offer Mile A Day+ in the app. No payment details are needed and nothing renews. Founding
					Runner status belongs to the account it was granted to and cannot be transferred.
				</p>
			</Section>

			<Section heading="Gifts">
				<p>
					You can buy a year of Mile A Day+ as a gift. Each gift purchase produces one code that can be redeemed once,
					by one account, for 12 months of Mile A Day+ starting when it is redeemed (or, if the recipient already has
					gifted time, when that time ends). Gift codes have no cash value, cannot be exchanged or resold, and do not
					renew. A code cannot be redeemed by an account that already has Mile A Day+ for life (a Founding Runner or a
					Lifetime purchase); it stays unused so it can be given to someone else. If a gift purchase is refunded, its
					code stops working and any time it granted ends.
				</p>
			</Section>

			<Section heading="Family Sharing">
				<p>
					Where Family Sharing is enabled for a plan, members of your Apple Family Sharing group may also use Mile A
					Day+ on their own Mile A Day accounts, as provided by Apple. Family access ends if the purchase ends, is
					refunded, or the member leaves the family group.
				</p>
			</Section>

			<Section heading="Refunds and Restoring Purchases">
				<p>
					All purchases are processed by Apple, and refund requests are handled by Apple under its policies; you can
					request one at reportaproblem.apple.com. We cannot issue refunds directly. If a purchase is refunded or
					revoked, the Mile A Day+ access it provided ends. Except where required by law, we do not provide refunds
					or credits for partial subscription periods.
				</p>
				<p>
					If you reinstall the app or switch devices, use Restore Purchases in Settings &rsaquo; Mile A Day+ to
					reconnect purchases made with your Apple ID. Purchases are linked to the Mile A Day account that made them.
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
					You may stop using the app and delete your account at any time from within the app. Deleting your account
					does not cancel an App Store subscription; cancel it in your Apple ID&rsquo;s Subscriptions settings. We may
					suspend or terminate your access if you violate these Terms or if we discontinue the service.
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
