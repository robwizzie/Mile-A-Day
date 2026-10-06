CREATE TABLE "desk_box_settings" (
	"key_id" uuid PRIMARY KEY NOT NULL,
	"style" smallint,
	"mascot" smallint,
	"rev" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "desk_commands" ADD COLUMN "key_id" uuid;--> statement-breakpoint
ALTER TABLE "desk_commands" ADD COLUMN "detail" varchar(60);--> statement-breakpoint
ALTER TABLE "desk_box_settings" ADD CONSTRAINT "desk_box_settings_key_id_fkey" FOREIGN KEY ("key_id") REFERENCES "public"."display_keys"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "desk_commands" ADD CONSTRAINT "desk_commands_key_id_fkey" FOREIGN KEY ("key_id") REFERENCES "public"."display_keys"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_desk_commands_key" ON "desk_commands" USING btree ("key_id","created_at" DESC NULLS FIRST);