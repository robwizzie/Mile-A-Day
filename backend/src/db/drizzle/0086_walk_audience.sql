CREATE TABLE "workout_feed_hides" (
	"user_id" text NOT NULL,
	"workout_id" varchar(255) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "workout_feed_hides_pkey" PRIMARY KEY("user_id","workout_id")
);
--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "on_profile" boolean;--> statement-breakpoint
ALTER TABLE "workout_feed_hides" ADD CONSTRAINT "workout_feed_hides_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;