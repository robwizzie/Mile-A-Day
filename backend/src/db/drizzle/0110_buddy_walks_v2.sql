CREATE TABLE "buddy_live_activities" (
	"session_id" varchar(32) NOT NULL,
	"user_id" text NOT NULL,
	"push_token" text NOT NULL,
	"environment" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "buddy_live_activities_pkey" PRIMARY KEY("session_id","user_id")
);
--> statement-breakpoint
CREATE TABLE "buddy_nearby_tokens" (
	"token" varchar(16) PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "buddy_out_alert_log" (
	"user_id" text NOT NULL,
	"friend_id" text NOT NULL,
	"local_date" date NOT NULL,
	"sent_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "buddy_out_alert_log_pkey" PRIMARY KEY("user_id","friend_id","local_date")
);
--> statement-breakpoint
CREATE TABLE "buddy_out_alerts" (
	"user_id" text NOT NULL,
	"friend_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "buddy_out_alerts_pkey" PRIMARY KEY("user_id","friend_id")
);
--> statement-breakpoint
ALTER TABLE "buddy_session_participants" ADD COLUMN "reporting_device" text;--> statement-breakpoint
ALTER TABLE "buddy_live_activities" ADD CONSTRAINT "buddy_live_activities_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."buddy_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_live_activities" ADD CONSTRAINT "buddy_live_activities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_nearby_tokens" ADD CONSTRAINT "buddy_nearby_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_out_alert_log" ADD CONSTRAINT "buddy_out_alert_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_out_alert_log" ADD CONSTRAINT "buddy_out_alert_log_friend_id_fkey" FOREIGN KEY ("friend_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_out_alerts" ADD CONSTRAINT "buddy_out_alerts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_out_alerts" ADD CONSTRAINT "buddy_out_alerts_friend_id_fkey" FOREIGN KEY ("friend_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_buddy_nearby_tokens_user" ON "buddy_nearby_tokens" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_buddy_nearby_tokens_expires" ON "buddy_nearby_tokens" USING btree ("expires_at");--> statement-breakpoint
CREATE INDEX "idx_buddy_out_alerts_friend" ON "buddy_out_alerts" USING btree ("friend_id");