CREATE TABLE "web_events" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"kind" varchar(8) NOT NULL,
	"path" varchar(200) NOT NULL,
	"target" varchar(80),
	"referrer_host" varchar(100),
	"utm_source" varchar(60),
	"utm_medium" varchar(60),
	"utm_campaign" varchar(80),
	"visitor" varchar(24) NOT NULL,
	"device" varchar(8),
	"country" varchar(2)
);
--> statement-breakpoint
ALTER TABLE "web_events" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE INDEX "idx_web_events_created_at" ON "web_events" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "idx_web_events_kind_created_at" ON "web_events" USING btree ("kind","created_at");