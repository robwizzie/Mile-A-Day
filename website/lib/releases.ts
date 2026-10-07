import {
  Activity,
  Award,
  BarChart3,
  Bell,
  Calendar,
  CalendarClock,
  CalendarRange,
  Camera,
  CirclePause,
  Clock,
  EyeOff,
  Flag,
  Flame,
  Footprints,
  Gift,
  Globe,
  HeartPulse,
  Images,
  LayoutGrid,
  Map,
  MapPinOff,
  Medal,
  MessageCircle,
  Mic,
  Plane,
  Route,
  Share2,
  Shield,
  Shirt,
  Smartphone,
  Sparkles,
  Swords,
  SwitchCamera,
  ThumbsUp,
  Timer,
  Trophy,
  UserPlus,
  Users,
  Utensils,
  Watch,
  type LucideIcon,
} from "lucide-react";

export type ReleaseFeature = {
  icon: LucideIcon;
  color: string;
  title: string;
  desc: string;
};

export type Release = {
  /** The App Store marketing version. */
  version: string;
  /** Month it shipped — a month, not a day, because that's what we can vouch for. */
  date: string;
  headline: string;
  summary: string;
  features: ReleaseFeature[];
};

// The site's copy of the app's release history, NEWEST FIRST. The app keeps
// the same notes in app/Mile A Day/Views/Components/WhatsNewView.swift
// (WhatsNewCatalog) — when a release ships, add it at the top here too and
// the home page's "New in" section and /updates both follow. Copy stays
// user-facing: what the feature does for you, no internal names.
export const RELEASES: Release[] = [
  {
    version: "1.2.07",
    date: "October 2026",
    headline: "Flamey gets a wardrobe",
    summary:
      "Every medal now unlocks something for Flamey to wear, your walks look like walks even without a map, and sharing got a lot better.",
    features: [
      {
        icon: Shirt,
        color: "#FF9F0A",
        title: "Flamey's Closet",
        desc: "On the Fun dashboard, every medal you earn unlocks something for Flamey to wear. Dress him up, give him a name, and save your favorite outfits.",
      },
      {
        icon: Flame,
        color: "#D94059",
        title: "Your Flamey, on your walks",
        desc: "Friends on Fun bring their Flamey to the feed: he runs their route beside them, and cheers from the track on walks without a map.",
      },
      {
        icon: Footprints,
        color: "#4A9FF5",
        title: "Every walk looks like a walk",
        desc: "Walks without a map get their own card: laps of a track indoors, a mile-by-mile pace ribbon everywhere else.",
      },
      {
        icon: Gift,
        color: "#BF5AF2",
        title: "Holiday medals",
        desc: "Get your mile in on a holiday and take home a medal for it, plus something festive for Flamey.",
      },
      {
        icon: SwitchCamera,
        color: "#30B0C7",
        title: "Front & Back photos",
        desc: "One press takes both cameras, mid-walk or after. Move the small photo to any corner, and tap it on the feed to flip the two.",
      },
      {
        icon: Share2,
        color: "#ff4d7d",
        title: "A new way to share",
        desc: "Swipe through finished cards for your walk, your streak, or your Flamey, then send one straight to Instagram Stories, Messages, or your photos.",
      },
      {
        icon: CalendarClock,
        color: "#5E5CE6",
        title: "Weekly Recap",
        desc: "Every Saturday evening, your week in review: miles, your best day, and how your friends did.",
      },
      {
        icon: MapPinOff,
        color: "#8E8E93",
        title: "Hide where you start and finish",
        desc: "Friends see your route with the first and last stretch trimmed off, so your front door stays yours. Choose how much in Settings.",
      },
      {
        icon: Users,
        color: "#63E6BE",
        title: "Buddy Walks, your rules",
        desc: "Choose who can join your walk, and when two friends start at once, combine into one walk with a single tap.",
      },
      {
        icon: Mic,
        color: "#FFD659",
        title: "Start with Siri",
        desc: "Start your mile from Siri, Shortcuts, the Action Button, or Control Center.",
      },
      {
        icon: Globe,
        color: "#34C759",
        title: "Now in more languages",
        desc: "Mile A Day speaks Spanish, Portuguese, French, and German, and follows your text size setting.",
      },
    ],
  },
  {
    version: "1.2.05",
    date: "September 2026",
    headline: "Nobody walks alone",
    summary:
      "Walk with friends in real time from anywhere, watch your route fly back from above, and race your own best.",
    features: [
      {
        icon: Users,
        color: "#D94059",
        title: "Buddy Walks",
        desc: "Start a walk or run together, from anywhere. Everyone counts down to the same second, your miles climb side by side, and friends can join partway through.",
      },
      {
        icon: Images,
        color: "#BF5AF2",
        title: "One walk, one post",
        desc: "A buddy walk goes to the feed once, with everyone's photos in the carousel and everyone's route on the map.",
      },
      {
        icon: Route,
        color: "#63E6BE",
        title: "Route Art",
        desc: "Your route, drawn rather than plotted — colored by the time of day you went out, with your miles ticked along the line.",
      },
      {
        icon: Plane,
        color: "#4A9FF5",
        title: "Fly your route back",
        desc: "Tap Flyover on any route and watch the whole walk from above, with your splits called out as you pass them.",
      },
      {
        icon: Timer,
        color: "#FF9F0A",
        title: "Ghost races & a voice in your ear",
        desc: "Race your own best over any distance and hear where you stand without breaking stride.",
      },
      {
        icon: Calendar,
        color: "#5E5CE6",
        title: "Weekly Challenges",
        desc: "One theme a week, with a target sized to what you actually run — alongside the daily challenge.",
      },
      {
        icon: Trophy,
        color: "#FFD659",
        title: "Compete, rebuilt",
        desc: "The tab opens on what's live and what you've won, and every daily challenge shows exactly how it was completed.",
      },
      {
        icon: HeartPulse,
        color: "#30B0C7",
        title: "Recovery Mode",
        desc: "Injured? Pause your streak instead of losing it. Your flame waits for you, bandaged, until you're ready.",
      },
      {
        icon: CirclePause,
        color: "#5AC8FA",
        title: "Pause mid-walk",
        desc: "Stop at a crossing or a shop. Paused time doesn't count against your pace, and it survives a locked phone.",
      },
      {
        icon: EyeOff,
        color: "#8E8E93",
        title: "Stealth Mode",
        desc: "Walk without recording a map at all. The mile still counts; the route is never stored.",
      },
      {
        icon: LayoutGrid,
        color: "#ff4d7d",
        title: "A dashboard you arrange",
        desc: "Switch cards on, off, and into the order you want.",
      },
      {
        icon: Utensils,
        color: "#34C759",
        title: "Well Earned",
        desc: "A light-hearted look at the energy your walks and runs burned, in Insights. Just for fun.",
      },
    ],
  },
  {
    version: "1.2.03",
    date: "July 2026",
    headline: "Your streak just got backup",
    summary:
      "A brand-new dashboard with a flame that really burns, Streak Tokens to protect your streak, and comments and collabs on the feed.",
    features: [
      {
        icon: LayoutGrid,
        color: "#D94059",
        title: "A brand-new Dashboard",
        desc: "Your mile, your streak, and your tokens in one view — Modern for calm and focused, or Fun for the animated flame buddy.",
      },
      {
        icon: Flame,
        color: "#FF9F0A",
        title: "A flame that really burns",
        desc: "A coal at midnight, shrinking as your day runs out, and a full blaze the moment you bank your mile — on your dashboard and the Streak Flame widget.",
      },
      {
        icon: Shield,
        color: "#FFD659",
        title: "Streak Tokens",
        desc: "Earn Double Down, Streak Save, and Streak Assist by running — then use them to protect your streak, or rescue a friend's.",
      },
      {
        icon: Sparkles,
        color: "#FFD659",
        title: "The Pure Flame",
        desc: "A gold flame on your profile when every day of your streak was earned on the day.",
      },
      {
        icon: Clock,
        color: "#4A9FF5",
        title: "Lock Screen countdown",
        desc: "Streak at risk in the evening? A live countdown appears on your Lock Screen with one-tap Start Mile.",
      },
      {
        icon: MessageCircle,
        color: "#BF5AF2",
        title: "Comments, mentions & collabs",
        desc: "Comment on friends' posts, @mention anyone, and share a run together as a collab — plus a Tagged tab for posts you're in.",
      },
      {
        icon: Images,
        color: "#ff4d7d",
        title: "A faster Feed",
        desc: "Swipe between friends' stories, spot fresh miles at a glance, and come back to a feed that's already refreshed.",
      },
      {
        icon: Camera,
        color: "#30B0C7",
        title: "Camera & composer",
        desc: "Pinch to zoom, a 0.5x ultra-wide lens, and a two-step composer that puts your caption first.",
      },
      {
        icon: Footprints,
        color: "#63E6BE",
        title: "Walks that agree",
        desc: "In-app tracking filters GPS noise and cross-checks your steps, so everyone on the same walk gets the same miles.",
      },
      {
        icon: Flag,
        color: "#5E5CE6",
        title: "Road to your next club",
        desc: "Insights maps your streak as a journey: milestones conquered, where you stand, and days to the next one.",
      },
      {
        icon: BarChart3,
        color: "#34C759",
        title: "Your month, wrapped",
        desc: "When the calendar flips, see your miles, your best day, and a card worth sharing.",
      },
      {
        icon: ThumbsUp,
        color: "#FF9900",
        title: "Unlimited hypes",
        desc: "Cheer your friends as much as you want — no daily cap.",
      },
    ],
  },
  {
    version: "1.2.0",
    date: "July 2026",
    headline: "The social update",
    summary:
      "Photo posts and stories, records for every distance, and daily challenges that went head-to-head.",
    features: [
      {
        icon: Images,
        color: "#ff4d7d",
        title: "Feed & Stories",
        desc: "Post a photo of your mile with your stats on it, share stories, and hype your friends' runs.",
      },
      {
        icon: Timer,
        color: "#D94059",
        title: "Race PRs",
        desc: "Automatic personal records for 5K, 10K, and every standard distance, tracked from your real runs.",
      },
      {
        icon: Award,
        color: "#FF9900",
        title: "3D Medals",
        desc: "Tiltable medals for your milestones, plus a whole shelf of new social awards to chase.",
      },
      {
        icon: Swords,
        color: "#D94059",
        title: "Head-to-Head",
        desc: "Daily challenges went competitive. Call out a friend and settle it by sundown.",
      },
      {
        icon: LayoutGrid,
        color: "#34C759",
        title: "New widgets",
        desc: "Your streak, today's progress, and a live friends leaderboard on your Home Screen.",
      },
      {
        icon: CalendarRange,
        color: "#5AC8FA",
        title: "Weekly recap",
        desc: "Your week in miles, wrapped.",
      },
      {
        icon: Map,
        color: "#BF5AF2",
        title: "Heatmap & Memories",
        desc: "Every route you've run on one glowing map, and yearly memories of your best days.",
      },
    ],
  },
  {
    version: "1.1.0",
    date: "June 2026",
    headline: "Settling in",
    summary:
      "A smoother first run, richer workout details, and friends that are easier to manage.",
    features: [
      {
        icon: Sparkles,
        color: "#D94059",
        title: "A smoother start",
        desc: "A refreshed onboarding that gets you from download to your first mile faster.",
      },
      {
        icon: Activity,
        color: "#4A9FF5",
        title: "Richer workout details",
        desc: "More of every walk and run, right where you tap into it.",
      },
      {
        icon: UserPlus,
        color: "#BF5AF2",
        title: "Friends, organized",
        desc: "Easier ways to find, add, and manage the people you walk with.",
      },
      {
        icon: Bell,
        color: "#FF9900",
        title: "Notifications in the app",
        desc: "A friend's news shows up as a banner even while you're using the app.",
      },
      {
        icon: Flame,
        color: "#FF9F0A",
        title: "Recalibrate your streak",
        desc: "One tap re-checks your streak against your Apple Health history.",
      },
    ],
  },
  {
    version: "1.0",
    date: "June 2026",
    headline: "Mile A Day launches",
    summary:
      "One mile, every day — on the App Store for iPhone and Apple Watch.",
    features: [
      {
        icon: Flame,
        color: "#D94059",
        title: "Daily mile streaks",
        desc: "Walk or run a mile a day and watch your streak climb.",
      },
      {
        icon: Activity,
        color: "#34C759",
        title: "Apple Health sync",
        desc: "Walks and runs from your watch, treadmill, and other apps count automatically.",
      },
      {
        icon: Smartphone,
        color: "#FF6B6B",
        title: "Start Mile",
        desc: "Track your walk or run right in the app with live GPS.",
      },
      {
        icon: Watch,
        color: "#8b1538",
        title: "Apple Watch",
        desc: "Check your progress and start your mile from your wrist.",
      },
      {
        icon: Users,
        color: "#BF5AF2",
        title: "Friends & nudges",
        desc: "Follow your friends' streaks and nudge anyone who hasn't gone out yet.",
      },
      {
        icon: Trophy,
        color: "#FFD659",
        title: "Competitions",
        desc: "Start a competition with friends and fight for the top of the leaderboard.",
      },
      {
        icon: Medal,
        color: "#FF9900",
        title: "Medals",
        desc: "Milestones for your streak, your miles, and your fastest mile.",
      },
    ],
  },
];

export const CURRENT_RELEASE = RELEASES[0];

/** URL-safe anchor for a release on /updates, e.g. "v1-2-07". */
export function releaseAnchor(version: string): string {
  return `v${version.replace(/\./g, "-")}`;
}
