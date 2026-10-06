CREATE TABLE "shoe_defaults" (
	"user_id" text NOT NULL,
	"activity" text NOT NULL,
	"shoe_id" uuid NOT NULL,
	"since" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "shoe_defaults_pkey" PRIMARY KEY("user_id","activity"),
	CONSTRAINT "shoe_defaults_activity_check" CHECK (activity IN ('walking', 'running'))
);
--> statement-breakpoint
ALTER TABLE "shoe_defaults" ADD CONSTRAINT "shoe_defaults_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "shoe_defaults" ADD CONSTRAINT "shoe_defaults_shoe_id_fkey" FOREIGN KEY ("shoe_id") REFERENCES "public"."shoes"("shoe_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_shoe_defaults_shoe" ON "shoe_defaults" USING btree ("shoe_id");--> statement-breakpoint
-- Carry each user's single default over as the default for BOTH activities,
-- dated from when it became the default (the old stamping rule exactly), so
-- nothing changes until someone splits them. Tiny table: the feature shipped
-- days ago.
INSERT INTO "shoe_defaults" ("user_id", "activity", "shoe_id", "since")
SELECT s."user_id", a.activity, s."shoe_id", COALESCE(s."default_since", s."created_at")
FROM "shoes" s
CROSS JOIN (VALUES ('walking'), ('running')) AS a(activity)
WHERE s."is_default" AND s."retired_at" IS NULL
ON CONFLICT DO NOTHING;
