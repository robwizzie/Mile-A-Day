CREATE TABLE "streak_coverage_refunds" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"local_date" date NOT NULL,
	"kind" varchar(32) NOT NULL,
	"source_user" text,
	"offer_id" uuid,
	"restored_last_used" date,
	"covered_at" timestamp with time zone,
	"refunded_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "streak_coverage" ADD COLUMN "prior_last_used" date;--> statement-breakpoint
ALTER TABLE "streak_coverage" ADD COLUMN "spent_stamp" date;--> statement-breakpoint
ALTER TABLE "streak_coverage" ADD COLUMN "offer_id" uuid;--> statement-breakpoint
ALTER TABLE "streak_coverage_refunds" ADD CONSTRAINT "streak_coverage_refunds_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "streak_coverage_refunds_user_idx" ON "streak_coverage_refunds" USING btree ("user_id","local_date");