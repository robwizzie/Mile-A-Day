CREATE TABLE "streak_pauses" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"started_on" date NOT NULL,
	"resumed_on" date,
	"frozen_streak" integer DEFAULT 0 NOT NULL,
	"expired_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "streak_pauses" ADD CONSTRAINT "streak_pauses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "streak_pauses_one_active_key" ON "streak_pauses" USING btree ("user_id") WHERE (resumed_on IS NULL);--> statement-breakpoint
CREATE INDEX "streak_pauses_user_idx" ON "streak_pauses" USING btree ("user_id","started_on");