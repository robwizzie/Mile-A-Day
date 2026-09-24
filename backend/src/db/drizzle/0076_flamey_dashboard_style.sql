CREATE TABLE "maintenance_runs" (
	"name" text PRIMARY KEY NOT NULL,
	"completed_at" timestamp with time zone NOT NULL,
	"detail" jsonb
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "dashboard_style" text;