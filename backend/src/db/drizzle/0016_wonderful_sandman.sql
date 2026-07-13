CREATE TABLE "h2h_matchups" (
	"local_date" date NOT NULL,
	"user_id" text NOT NULL,
	"rival_id" text NOT NULL,
	"mutual" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone,
	"won" boolean,
	"notified_at" timestamp with time zone,
	CONSTRAINT "h2h_matchups_pkey" PRIMARY KEY("local_date","user_id")
);
--> statement-breakpoint
ALTER TABLE "h2h_matchups" ADD CONSTRAINT "h2h_matchups_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "h2h_matchups" ADD CONSTRAINT "h2h_matchups_rival_id_fkey" FOREIGN KEY ("rival_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;