CREATE TABLE "display_messages" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"to_user_id" text NOT NULL,
	"from_user_id" text,
	"body" varchar(80) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
ALTER TABLE "display_messages" ADD CONSTRAINT "display_messages_to_user_id_fkey" FOREIGN KEY ("to_user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "display_messages" ADD CONSTRAINT "display_messages_from_user_id_fkey" FOREIGN KEY ("from_user_id") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_display_messages_to" ON "display_messages" USING btree ("to_user_id","created_at" DESC NULLS FIRST);