CREATE TABLE "friend_request_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"sender_id" text NOT NULL,
	"target_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now()
);
--> statement-breakpoint
CREATE INDEX "idx_friend_request_log_lookup" ON "friend_request_log" USING btree ("sender_id","target_id","created_at" DESC NULLS FIRST);