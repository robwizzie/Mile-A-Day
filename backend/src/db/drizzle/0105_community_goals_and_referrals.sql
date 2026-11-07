CREATE TABLE "community_goal_push_log" (
	"goal_id" text NOT NULL,
	"user_id" text NOT NULL,
	"kind" text NOT NULL,
	"sent_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "community_goal_push_log_pkey" PRIMARY KEY("goal_id","user_id","kind")
);
--> statement-breakpoint
ALTER TABLE "community_goal_push_log" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "community_goal_totals" (
	"goal_id" text PRIMARY KEY NOT NULL,
	"total_miles" numeric DEFAULT '0' NOT NULL,
	"walkers" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "community_goal_totals" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "community_goals" (
	"goal_id" text PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"description" text NOT NULL,
	"target_miles" numeric NOT NULL,
	"starts_on" date NOT NULL,
	"ends_on" date NOT NULL,
	"checkpoints" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"reward_tiers" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"rewards_granted_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "community_goals" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "referral_offer_codes" (
	"code" text PRIMARY KEY NOT NULL,
	"assigned_to" text,
	"assigned_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "referral_offer_codes" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "referral_rewards" (
	"user_id" text NOT NULL,
	"reward_count" integer NOT NULL,
	"earned_at" timestamp with time zone DEFAULT now() NOT NULL,
	"claimed_at" timestamp with time zone,
	CONSTRAINT "referral_rewards_pkey" PRIMARY KEY("user_id","reward_count")
);
--> statement-breakpoint
ALTER TABLE "referral_rewards" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "referrals" (
	"referee_id" text PRIMARY KEY NOT NULL,
	"referrer_id" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"origin" text DEFAULT 'picked' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"qualified_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "referrals" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "community_goal_push_log" ADD CONSTRAINT "community_goal_push_log_goal_id_community_goals_goal_id_fk" FOREIGN KEY ("goal_id") REFERENCES "public"."community_goals"("goal_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "community_goal_push_log" ADD CONSTRAINT "community_goal_push_log_user_id_users_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "community_goal_totals" ADD CONSTRAINT "community_goal_totals_goal_id_community_goals_goal_id_fk" FOREIGN KEY ("goal_id") REFERENCES "public"."community_goals"("goal_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "referral_offer_codes" ADD CONSTRAINT "referral_offer_codes_assigned_to_users_user_id_fk" FOREIGN KEY ("assigned_to") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "referral_rewards" ADD CONSTRAINT "referral_rewards_user_id_users_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "referrals" ADD CONSTRAINT "referrals_referee_id_users_user_id_fk" FOREIGN KEY ("referee_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "referrals" ADD CONSTRAINT "referrals_referrer_id_users_user_id_fk" FOREIGN KEY ("referrer_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_referral_offer_codes_owner" ON "referral_offer_codes" USING btree ("assigned_to");--> statement-breakpoint
CREATE INDEX "idx_referrals_referrer" ON "referrals" USING btree ("referrer_id","status");