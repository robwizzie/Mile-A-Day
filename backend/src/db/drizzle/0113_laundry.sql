CREATE TABLE "laundry_loads" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"plug_id" uuid NOT NULL,
	"machine" varchar(16) NOT NULL,
	"started_at" timestamp with time zone NOT NULL,
	"ended_at" timestamp with time zone NOT NULL,
	"seconds" integer NOT NULL,
	"trace" text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE TABLE "laundry_plugs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"machine" varchar(16) NOT NULL,
	"key_hash" varchar(64) NOT NULL,
	"key_prefix" varchar(16) NOT NULL,
	"state" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone,
	"revoked_at" timestamp with time zone,
	CONSTRAINT "laundry_plugs_key_hash_key" UNIQUE("key_hash"),
	CONSTRAINT "laundry_plugs_machine_check" CHECK (machine IN ('washer', 'dryer'))
);
--> statement-breakpoint
ALTER TABLE "laundry_loads" ADD CONSTRAINT "laundry_loads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "laundry_loads" ADD CONSTRAINT "laundry_loads_plug_id_fkey" FOREIGN KEY ("plug_id") REFERENCES "public"."laundry_plugs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "laundry_plugs" ADD CONSTRAINT "laundry_plugs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_laundry_loads_user" ON "laundry_loads" USING btree ("user_id","ended_at" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_laundry_plugs_user" ON "laundry_plugs" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "laundry_plugs_one_live" ON "laundry_plugs" USING btree ("user_id","machine") WHERE (revoked_at IS NULL);