CREATE TABLE "special_event_push_log" (
	"event_id" text NOT NULL,
	"user_id" text NOT NULL,
	"kind" text NOT NULL,
	"sent_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "special_event_push_log_pkey" PRIMARY KEY("event_id","user_id","kind")
);
--> statement-breakpoint
ALTER TABLE "special_event_push_log" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "special_event_push_log" ADD CONSTRAINT "special_event_push_log_user_id_users_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;