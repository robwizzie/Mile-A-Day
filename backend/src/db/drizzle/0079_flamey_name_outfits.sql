CREATE TABLE "flamey_outfits" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"position" integer NOT NULL,
	"name" text NOT NULL,
	"look" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "flamey_name" text;--> statement-breakpoint
ALTER TABLE "flamey_outfits" ADD CONSTRAINT "flamey_outfits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_flamey_outfits_user" ON "flamey_outfits" USING btree ("user_id","position");