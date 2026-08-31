CREATE TABLE "referral_aliases" (
	"alias" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"created_by" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "referral_aliases" ADD CONSTRAINT "referral_aliases_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_referral_aliases_user" ON "referral_aliases" USING btree ("user_id");