import type { Metadata } from 'next';
import { LegalPage, Section } from '@/components/legal-page';
import { ogVideos } from '../_og/video/meta';

export const metadata: Metadata = {
	title: 'Privacy Policy',
	description: 'How Mile A Day collects, uses, and protects your data.',
	alternates: { canonical: '/privacy' },
	// A page's openGraph/twitter REPLACE the root ones, so restate what a share
	// needs; the card image comes from this segment's opengraph-image.
	openGraph: {
		title: 'Privacy Policy | Mile A Day',
		description: 'How Mile A Day collects, uses, and protects your data.',
		url: '/privacy',
		type: 'website',
		siteName: 'Mile A Day',
		videos: ogVideos('/privacy/og.mp4')
	},
	twitter: {
		card: 'summary_large_image',
		site: '@mileadayapp',
		title: 'Privacy Policy | Mile A Day',
		description: 'How Mile A Day collects, uses, and protects your data.'
	}
};

export default function PrivacyPage() {
	return (
		<LegalPage title="PRIVACY POLICY" lastUpdated="November 6, 2026">
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
					<span className="font-semibold text-[#f5f5f5]">Location and GPS routes.</span> The precise path of your outdoor walks and
					runs, including when you were at each point along it. See{' '}
					<span className="font-semibold text-[#f5f5f5]">Location and Route Data</span> below for exactly what we collect and who can
					see it.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Social activity.</span> Friend connections, competitions you
					join, and related activity needed to operate the social features of the app.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Purchase information.</span> If you buy Mile A Day+ or a gift,
					Apple sends us a signed record of the transaction: the product, purchase and expiry dates, transaction
					identifiers, whether it is a free trial or shared through Family Sharing, renewal status, and whether it was
					refunded. We link this to your account to turn Mile A Day+ on and off and to manage gift codes. We never
					receive your payment card or billing details; Apple handles payment.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Website sign-up lists.</span> If you join a list on our
					website (like the Android waitlist or &ldquo;I&apos;d buy one&rdquo; for the Mile A Day desk box), we keep
					the email address and any name or answers you give us, and use them only to contact you about that product.
					Email us to be removed at any time.
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
					<li>To draw your routes for you and, depending on your settings, for other people in the app.</li>
					<li>To send notifications you have enabled, such as streak reminders.</li>
					<li>To provide Mile A Day+ when you have it, including gifts and Family Sharing.</li>
					<li>To maintain, troubleshoot, and improve the app.</li>
				</ul>
			</Section>

			<Section heading="HealthKit Data">
				<p>
					Health data accessed through Apple HealthKit is used solely to provide the app&rsquo;s fitness tracking and
					social features, including the route sharing and the aggregate location view described below. We do not use
					HealthKit data for advertising or marketing, and we do not sell it or share it with data brokers. You can
					review and revoke the app&rsquo;s HealthKit permissions at any time in the iOS Settings app under Privacy
					&amp; Security &rarr; Health.
				</p>
			</Section>

			<Section heading="Location and Route Data">
				<p>
					A GPS route shows where you were, and a route you walk often can reveal where you live, work, or spend time.
					This section explains what we collect, who can see it, and how to limit it.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">What we collect.</span> For a workout with GPS data, we store a simplified copy
					of its route: up to 300 points, each with its latitude and longitude (accurate to about one meter), its
					altitude when available, and the time it was recorded. Indoor workouts and workouts without GPS have no route.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Where it comes from.</span> When you track a workout in the app, we use your
					device&rsquo;s location, with your permission, while that workout is in progress, including if the app is in
					the background during it. We do not collect your location at other times. Routes also come from Apple
					HealthKit, with your permission, so workouts recorded by Apple Watch or another app can have routes too. The
					app reads routes from HealthKit to show you, and to upload as described below.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">When it is uploaded.</span> Routes are sent to our servers when your workouts
					sync, usually shortly after a workout ends. The app also adds routes for past workouts automatically, going
					back up to two years, and for your full history if you choose &ldquo;Add maps to old walks&rdquo; in Settings.
					Routes are uploaded unless Stealth Mode applies, and this happens whatever your choices below about showing
					them to other people. We keep your own routes so you can see them on your maps and across devices.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Who can see your routes by default.</span> Your accepted friends can see the
					map of your routes on your posts and workouts, and can play a flyover replay of them. By default, about 1/8
					mile is hidden from each end of the route, and people you block never see it. If you skip the photo after a
					mile, the app also posts a route and stats card to your friends&rsquo; feeds unless you turn off &ldquo;Post my
					route when I skip.&rdquo;
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Your controls.</span> You can change these at any time in Settings &rarr;
					Privacy:
				</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>
						<span className="font-semibold text-[#f5f5f5]">Who can see my workouts.</span> &ldquo;Friends only&rdquo; is the default.
						&ldquo;Everyone&rdquo; lets any Mile A Day user see your routes. &ldquo;Only me&rdquo; limits them to you,
						apart from anyone who posts a Buddy Walk you joined.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Show route maps.</span> Turn this off and others see your posts and workouts
						without the map. Your routes stay stored on our servers.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Map on new posts.</span> Choose whether new posts start with the map on or
						off. You can also turn the map off on an individual post, before or after sharing it.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Hide start &amp; end.</span> Hide 1/8, 1/4, 1/2, or 1 mile from each end of
						what others see, or turn this off to show the whole route. This also applies to routes you have already
						posted. A short route may show no map at all.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Route flyovers.</span> Let friends play flyovers of your routes, or keep
						them to yourself.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Stealth Mode.</span> Routes from workouts recorded while Stealth Mode is on
						are never stored on our servers and stay hidden even after you turn it off. Friends can still see your
						distance, pace, and time. When you turn it on, you can also remove routes from up to the last 30 days.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Hide this route from friends.</span> On a single workout, this permanently
						deletes that route from our servers. The copy in Apple Health on your device is not affected.
					</li>
				</ul>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Things these controls do not cover.</span>
				</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>
						A route sticker you add to a post shows the whole shape of your walk, without a map, to anyone who can see
						that post. It is not trimmed by Hide start &amp; end or removed by Show route maps, and it stays until you
						delete the post, even if you later hide that route. Stealth Mode workouts cannot use one.
					</li>
					<li>
						If someone posts a Buddy Walk you were part of, your route can appear on that post, under your own route
						settings, to the people who can see it. They may not be your friends.
					</li>
					<li>
						Removing a route or changing a setting does not reach anything people already saved, screenshotted, or
						received from you outside the app, including share cards you exported.
					</li>
				</ul>
				<p>
					<span className="font-semibold text-[#f5f5f5]">What is not shared.</span> Friends can see that you are out on a walk right
					now if you allow it, but never where. Buddy Walks share distance and progress during the walk, not your live
					position. Your routes do not appear on our public website pages, including shared profile and post links.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Aggregate use.</span> To understand where our members are, we use the middle
					of your recent routes to place you in a grid square about 17 miles wide. We view this internally as counts per
					square, not as individual people or streets. Workouts in Stealth Mode are not included, and this is not
					affected by Show route maps.
				</p>
			</Section>

			<Section heading="How We Share Information">
				<p>We do not sell your personal information. We share information only in these limited cases:</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>
						<span className="font-semibold text-[#f5f5f5]">With other users.</span> Your username, profile photo,
						streak, and competition results are visible to friends and competition participants, as that is the core
						purpose of the app. Your GPS routes are also visible to other users according to your settings, as described
						in Location and Route Data. By default, that means your accepted friends.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Service providers.</span> With infrastructure providers
						that host our servers and deliver the service, who are only permitted to use the data to provide those
						services. Maps in the app are drawn with Apple Maps, so your device requests map imagery for the area of a
						route from Apple.
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
				<p>
					GPS routes do not expire: we keep them until they are deleted through Stealth Mode or Hide this route from
					friends, or until you delete your account. Deleting a single workout removes it from your history, but its
					stored route stays on our servers, and a post made from that workout keeps its map until you delete the post.
					To delete the route itself, use Hide this route from friends on the workout first, or contact us. Revoking
					HealthKit or location access stops new routes from being added, but does not delete routes we already store.
				</p>
			</Section>

			<Section heading="Your Choices">
				<ul className="list-disc space-y-2 pl-6">
					<li>Control HealthKit access in iOS Settings at any time.</li>
					<li>Control location access in iOS Settings at any time.</li>
					<li>Choose who can see your routes, or stop routes being stored, in Settings &rarr; Privacy in the app.</li>
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
