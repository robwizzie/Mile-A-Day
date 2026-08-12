CREATE TABLE "user_daily_challenges" (
	"user_id" text NOT NULL,
	"local_date" date NOT NULL,
	"challenge_key" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_daily_challenges_pkey" PRIMARY KEY("user_id","local_date")
);
--> statement-breakpoint
ALTER TABLE "user_daily_challenges" ADD CONSTRAINT "user_daily_challenges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_daily_challenges" ADD CONSTRAINT "user_daily_challenges_challenge_key_fkey" FOREIGN KEY ("challenge_key") REFERENCES "public"."daily_challenges"("challenge_key") ON DELETE no action ON UPDATE no action;