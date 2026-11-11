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
		<LegalPage title="Privacy Policy" lastUpdated="November 10, 2026">
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
					receive an Apple-provided identifier and, if you share them, your name and email address. If you choose to hide
					your email, Apple provides a private relay address instead of your real email. We use this information to
					create and maintain your account.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Profile information.</span> Your chosen username, first and
					last name, and optional bio, profile photo, and banner image, plus your daily goal and app personalization
					such as your Flamey&rsquo;s name and look. Part of your profile is public. See{' '}
					<span className="font-semibold text-[#f5f5f5]">How We Share Information</span> below.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Setup answers.</span> During setup you can tell us how you heard about Mile A Day (and, if you
					type it, a detail such as a friend&rsquo;s username), what you want from the app, and your experience level.
					These questions are optional.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Health and fitness data.</span> With your explicit permission,
					the app reads your workouts, walking and running distance, active energy, step counts, and workout routes
					from Apple HealthKit to calculate your daily mile, streaks, and personal records. This data is read on your
					device and synced to our servers to power streaks, leaderboards, and competitions.
				</p>
				<p>What we store on our servers:</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>
						For each workout: its type (such as walk, run, cycle, or hike), date, time zone offset, distance, duration,
						moving time, mile splits and pace, calories, steps, and whether it was indoors.
					</li>
					<li>
						Which app recorded the workout, such as Apple Workout or another fitness app, as that app&rsquo;s
						identifier.
					</li>
					<li>
						Your daily step count. The app sends this as you go and for the last 30 days, and it also sends past days
						on which you reached the step goal, as far back as Health and your account allow.
					</li>
					<li>Workouts you enter by hand or import from another service&rsquo;s export file.</li>
				</ul>
				<p>
					Your distance during a tracked workout is also sent to us as you go, so friends can follow along (see{' '}
					<span className="font-semibold text-[#f5f5f5]">How We Share Information</span>).
				</p>
				<p>
					Some health data stays on your device. On Apple Watch, the app reads your heart rate to show it during a
					workout and saves it to Apple Health with that workout, but heart rate is not sent to our servers. Body weight
					is never uploaded. The current app does not read it, and its calorie estimates use a typical adult&rsquo;s
					weight. The app also saves workouts you complete, with their distance, active energy, and routes, to Apple
					Health.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Motion and treadmill data.</span> For indoor workouts, the app can use your device&rsquo;s
					motion and pedometer sensors, or read speed and distance from a gym treadmill over Bluetooth. These readings
					are used on your device to measure the workout. Only the resulting distance and workout details above are
					uploaded.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Location and GPS routes.</span> The precise path of your outdoor walks and
					runs, including when you were at each point along it. See{' '}
					<span className="font-semibold text-[#f5f5f5]">Location and Route Data</span> below for exactly what we collect and who can
					see it.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Posts and photos.</span> The photos you post, including front
					and back camera pairs, and the captions, stickers, tagged people, and workout stats on them. We also store
					whether a post&rsquo;s photo came from the camera or your library, and your story highlights. The camera is used only
					when you take a photo or scan a friend&rsquo;s QR code, and QR scanning stays on your device. If you add a
					picture from your library, the app shows you photos taken during that workout, and only the one you
					choose is uploaded. We re-encode uploaded photos, which removes embedded information such as location. Photos
					you save go to your photo library; we do not see them unless you post them.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Social activity.</span> Friend connections and requests, competitions and Buddy Walks you join,
					comments, reactions and hypes, nudges, who viewed your stories, and related activity needed to operate
					the social features of the app.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Shoes.</span> If you track shoes, we store each shoe&rsquo;s name, brand, colorway, photo, mileage,
					replacement goal, and the workouts you assign it to.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Reports and blocks.</span> If you report a post or comment, we store your report, including the
					reason and any details you add. We also store who you have blocked.
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
					<span className="font-semibold text-[#f5f5f5]">Merch orders.</span> Our store at mileaday.shop checks out on
					Shopify, not on our systems. Shopify receives what you enter at checkout, and Tapstitch makes and ships orders.
				</p>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Device, usage, and diagnostic data.</span> Information we use to run the service and fix problems:
				</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>
						<span className="font-semibold text-[#f5f5f5]">Sign-in records.</span> Your IP address and device or browser type (user agent) each time your
						session is created or renewed, along with authentication tokens.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Notifications.</span> Your device&rsquo;s push notification token, which widgets you have
						installed, and a record of notifications sent to you.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Crash and performance reports.</span> The app sends us reports from Apple&rsquo;s MetricKit about
						crashes, hangs, and how the app is performing. They include your app version, iOS version, device model, and
						technical traces of what the app was doing, and are linked to your account.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Feature usage.</span> Which of certain features you use, such as a share destination or a Mile
						A Day+ screen, linked to your account.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Error logs.</span> When a request fails, we log it with your account ID, the address that was
						requested (which can include text you searched for), and technical details. A failed sign-in can log the
						email address it used.
					</li>
				</ul>
				<p>
					<span className="font-semibold text-[#f5f5f5]">Website visits.</span> Our websites use Vercel Analytics to measure visits, and
					mileaday.run also counts its own page views and the links and buttons clicked on it (for example, how many visits
					tap through to the App Store), along with the page, the site that linked you there, your device type and country.
					We do not store your IP address for this: each visit is counted under a code made from your IP address and browser
					with a key that changes every day, so a visit can&rsquo;t be traced back to you or linked to your visits on other
					days. If your browser sends Do Not Track or Global Privacy Control, we don&rsquo;t count you at all. Our public pages
					do not set cookies, but your browser sends your IP address to any site you visit, including ours.
				</p>
				<p>
					The app contains no advertising or third-party analytics software, and we do not track you across other
					companies&rsquo; apps or websites.
				</p>
			</Section>

			<Section heading="How We Use Your Information">
				<ul className="list-disc space-y-2 pl-6">
					<li>To create your account and authenticate you when you sign in.</li>
					<li>To calculate and display your daily mile progress, streaks, and personal records.</li>
					<li>To power friends, posts, stories, leaderboards, and competitions.</li>
					<li>
						To track referrals. If you pick who referred you, they can see your first name, profile photo, and how many
						days you&rsquo;ve walked until your referral counts.
					</li>
					<li>To add your miles to community goals, which only ever show combined totals and your own contribution.</li>
					<li>To show your public profile.</li>
					<li>To draw your routes for you and, depending on your settings, for other people in the app.</li>
					<li>To send notifications you have enabled, such as streak reminders.</li>
					<li>To provide Mile A Day+ when you have it, including gifts and Family Sharing.</li>
					<li>To maintain, troubleshoot, and improve the app, including finding the cause of crashes and errors.</li>
					<li>To understand which features people use and how they found the app.</li>
					<li>To keep accounts secure, review reports, and enforce our Terms.</li>
				</ul>
			</Section>

			<Section heading="HealthKit Data">
				<p>
					Health data accessed through Apple HealthKit is used solely to provide the app&rsquo;s fitness tracking and
					social features, including the route sharing and the aggregate location view described below and the total
					miles on your public profile. We do not use
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
					<span className="font-semibold text-[#f5f5f5]">Live route sharing on Buddy Walks.</span> This is off by default. During an
					outdoor Buddy Walk, you can turn it on for that one walk, and only other people on the walk who also turned
					it on can see your route as you go. GPS points are uploaded during the walk only once you have moved past them
					by your Hide start &amp; end distance, so your start and your final stretch are not sent live. It is not
					available while Stealth Mode is on, while Show route maps is off, or if Who can see my workouts is set to
					&ldquo;Only me.&rdquo; We delete these live points from our servers when the walk ends. Your finished route is
					separate: it syncs and is shared under the settings described in this section.
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
					now, and your distance so far, if you allow it, but never where. Unless you turn on live route sharing for a Buddy Walk, Buddy Walks share
					distance and progress during the walk, not your position. Your routes do not appear on our public website pages, including shared profile and post links.
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
						<span className="font-semibold text-[#f5f5f5]">With anyone, without an account.</span> Everyone has a public profile page at
						mileaday.run/u/your-username, and anyone can open it, whether or not they use Mile A Day. It always shows your
						name, username, bio, profile photo, banner, and current streak. Unless Who can see my workouts is set to
						&ldquo;Only me,&rdquo; it also shows your lifetime miles, friend count, and up to five medals. Search engines
						may list these pages. A link to a post you share shows your name, username, photo, and streak, but
						not the post&rsquo;s photo, caption, or route. Profile photos, banners, and shoe photos are stored at web
						addresses that do not need a sign-in.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">With other Mile A Day users.</span> Anyone signed in can find you by name or username and see
						your name, username, bio, profile photo, and streak, even if you are not friends.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">With friends and people in your activities.</span> By default, accepted friends can see your
						posts, stories, comments, workouts and their stats (such as distance, pace, time, calories, and steps), medals,
						and streaks. They also appear on leaderboards with you, and can see that you are out
						on a tracked workout and your distance so far unless you turn that off. People in your competitions and
						Buddy Walks see your results. Tagged people and people you post with appear on the post. You can
						see who viewed your stories, and others can see the same for theirs. Setting Who can see my workouts to
						&ldquo;Everyone&rdquo; lets any Mile A Day user see your posts and workouts. Your GPS routes are visible
						according to your settings, as described in Location and Route Data. By default, that means your accepted
						friends.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Example posts.</span> We choose a small number of posts to show as examples in the app&rsquo;s
						onboarding, including to people who are not signed in. These show the post&rsquo;s photo, caption, distance,
						streak, and date, and the author&rsquo;s username and profile photo. If you would like your post taken
						out, email us.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Service providers.</span> With infrastructure providers
						that host our servers and deliver the service, who are only permitted to use the data to provide those
						services. These include Cloudflare, which carries traffic to our servers, and Vercel, which hosts our websites
						and provides website analytics. Apple handles Sign in with Apple and purchases, and delivers push notifications,
						so the text of a notification, which can include a friend&rsquo;s name, passes through Apple. Shopify and
						Tapstitch handle merch orders. Maps in the app are drawn with Apple Maps, so your device requests map imagery
						for the area of a route from Apple.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Our team and tools.</span> Authorized staff can view account details, posts, reports,
						diagnostics, and logs to support users, review reports, and run the service. Our team may use AI assistants,
						currently Anthropic&rsquo;s Claude, to help query and maintain our database, so data they look up can
						pass through that tool. We do not send your data to AI services as a feature of the app.
					</li>
					<li>
						<span className="font-semibold text-[#f5f5f5]">Things you share yourself.</span> If you export a share card or use the iOS share sheet or
						Messages, what you send is handled by the app you choose.
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
					the app, which removes your profile, workouts, step counts, shoes, friends, posts, comments, reports, and
					notification and crash data from our servers. Your profile photo, banner, and shoe photos are deleted right
					away. Post photos are deleted by a nightly cleanup within a few days. You may also request deletion by
					contacting us at the email below.
				</p>
				<p>Some information stays after you delete your account:</p>
				<ul className="list-disc space-y-2 pl-6">
					<li>Purchase and gift records, which we keep for our financial records.</li>
					<li>
						Internal logs, including error logs, feature usage, and records of some notifications and database
						changes. These can include your account ID, and error logs can contain the details described above.
					</li>
					<li>Competitions and Buddy Walks you took part in, without your name attached.</li>
					<li>Anything other people saved, or received from you outside the app.</li>
				</ul>
				<p>
					Deleting content does not always erase it right away. A post or comment you delete disappears from the app,
					but we keep it, including any photo, until you delete your account, so that it can be restored. A story stops
					showing after 24 hours, and the post behind it stays stored the same way. A deleted workout is kept marked as
					deleted. To have specific content permanently removed sooner, contact us.
				</p>
				<p>
					Crash and performance reports are kept for 90 days. Sign-in records are kept until you delete your account.
					Error logs and feature usage have no set deletion date.
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
					<li>
						Hide your lifetime miles, friend count, and medals from your public profile by setting Who can see my
						workouts to &ldquo;Only me.&rdquo;
					</li>
					<li>Report posts and comments, and block other users, within the app.</li>
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
