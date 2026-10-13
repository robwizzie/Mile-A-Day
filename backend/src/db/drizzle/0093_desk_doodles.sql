CREATE TABLE "desk_doodles" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"to_user_id" text NOT NULL,
	"from_user_id" text NOT NULL,
	"pixels" varchar(2048) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
ALTER TABLE "desk_doodles" ADD CONSTRAINT "desk_doodles_to_user_id_fkey" FOREIGN KEY ("to_user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "desk_doodles" ADD CONSTRAINT "desk_doodles_from_user_id_fkey" FOREIGN KEY ("from_user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_desk_doodles_to" ON "desk_doodles" USING btree ("to_user_id","created_at" DESC NULLS FIRST);