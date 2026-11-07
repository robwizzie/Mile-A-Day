CREATE TABLE "buddy_live_routes" (
	"session_id" varchar(32) NOT NULL,
	"user_id" text NOT NULL,
	"points" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"point_count" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "buddy_live_routes_pkey" PRIMARY KEY("session_id","user_id")
);
--> statement-breakpoint
ALTER TABLE "buddy_live_routes" ADD CONSTRAINT "buddy_live_routes_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."buddy_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_live_routes" ADD CONSTRAINT "buddy_live_routes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_buddy_live_routes_updated_at" ON "buddy_live_routes" USING btree ("updated_at");