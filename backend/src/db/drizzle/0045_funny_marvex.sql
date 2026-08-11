CREATE TABLE "streak_assist_offers" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"donor_id" text NOT NULL,
	"recipient_id" text NOT NULL,
	"initiator" varchar(12) NOT NULL,
	"donor_date" date,
	"target_date" date NOT NULL,
	"status" varchar(12) DEFAULT 'pending' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "streak_assist_offers" ADD CONSTRAINT "streak_assist_offers_donor_id_fkey" FOREIGN KEY ("donor_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "streak_assist_offers" ADD CONSTRAINT "streak_assist_offers_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "streak_assist_offers_pending_key" ON "streak_assist_offers" USING btree ("donor_id","recipient_id","target_date") WHERE ((status)::text = 'pending'::text);--> statement-breakpoint
CREATE INDEX "streak_assist_offers_recipient_idx" ON "streak_assist_offers" USING btree ("recipient_id","status");--> statement-breakpoint
CREATE INDEX "streak_assist_offers_donor_idx" ON "streak_assist_offers" USING btree ("donor_id","donor_date");