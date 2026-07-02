CREATE TABLE "workout_routes" (
	"workout_id" varchar(255) PRIMARY KEY NOT NULL,
	"route" jsonb NOT NULL,
	"point_count" integer NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "is_auto" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "include_route" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "workout_routes" ADD CONSTRAINT "workout_routes_workout_id_fkey" FOREIGN KEY ("workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE cascade ON UPDATE no action;