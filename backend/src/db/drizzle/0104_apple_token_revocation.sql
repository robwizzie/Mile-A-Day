CREATE TABLE "apple_sign_in_tokens" (
	"user_id" text PRIMARY KEY NOT NULL,
	"encrypted_refresh_token" text NOT NULL,
	"client_id" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "apple_sign_in_tokens" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "apple_token_revocations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"encrypted_refresh_token" text NOT NULL,
	"client_id" text NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"next_attempt_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "apple_token_revocations" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "apple_sign_in_tokens" ADD CONSTRAINT "apple_sign_in_tokens_user_id_users_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_apple_token_revocations_due" ON "apple_token_revocations" USING btree ("next_attempt_at");