CREATE TABLE "buddy_looking" (
	"user_id" text PRIMARY KEY NOT NULL,
	"activity_type" varchar(16),
	"looking_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "buddy_looking" ADD CONSTRAINT "buddy_looking_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_buddy_looking_looking_at" ON "buddy_looking" USING btree ("looking_at" DESC NULLS FIRST);