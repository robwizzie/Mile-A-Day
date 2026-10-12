CREATE TABLE "desk_push_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"kind" varchar(32) NOT NULL,
	"text" varchar(300) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "desk_push_log" ADD CONSTRAINT "desk_push_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_desk_push_log_user" ON "desk_push_log" USING btree ("user_id","created_at" DESC NULLS FIRST);