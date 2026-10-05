CREATE TABLE "shoes" (
	"shoe_id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"name" text NOT NULL,
	"brand" text,
	"colorway" text,
	"image_url" text,
	"starting_miles" double precision DEFAULT 0 NOT NULL,
	"replace_at_miles" double precision,
	"is_default" boolean DEFAULT false NOT NULL,
	"default_since" timestamp with time zone,
	"retired_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "shoes_name_check" CHECK (char_length(name) BETWEEN 1 AND 120)
);
--> statement-breakpoint
CREATE TABLE "workout_shoes" (
	"user_id" text NOT NULL,
	"workout_id" varchar(255) NOT NULL,
	"shoe_id" uuid,
	"assigned_by" text NOT NULL,
	"assigned_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "workout_shoes_pkey" PRIMARY KEY("user_id","workout_id"),
	CONSTRAINT "workout_shoes_assigned_by_check" CHECK (assigned_by IN ('default', 'user'))
);
--> statement-breakpoint
ALTER TABLE "shoes" ADD CONSTRAINT "shoes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_shoes" ADD CONSTRAINT "workout_shoes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_shoes" ADD CONSTRAINT "workout_shoes_shoe_id_fkey" FOREIGN KEY ("shoe_id") REFERENCES "public"."shoes"("shoe_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_shoes_user" ON "shoes" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "shoes_one_default_per_user" ON "shoes" USING btree ("user_id") WHERE is_default;--> statement-breakpoint
CREATE INDEX "idx_workout_shoes_shoe" ON "workout_shoes" USING btree ("shoe_id") WHERE shoe_id IS NOT NULL;