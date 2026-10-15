CREATE TABLE "plus_gifts" (
	"code" varchar(16) PRIMARY KEY NOT NULL,
	"purchaser_id" text NOT NULL,
	"transaction_id" text NOT NULL,
	"product_id" text NOT NULL,
	"environment" text NOT NULL,
	"months" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"redeemed_by" text,
	"redeemed_at" timestamp with time zone,
	"grant_starts_at" timestamp with time zone,
	"grant_ends_at" timestamp with time zone,
	"voided_at" timestamp with time zone,
	CONSTRAINT "plus_gifts_transaction_unique" UNIQUE("transaction_id")
);
--> statement-breakpoint
CREATE TABLE "plus_purchases" (
	"original_transaction_id" text NOT NULL,
	"user_id" text NOT NULL,
	"product_id" text NOT NULL,
	"transaction_id" text NOT NULL,
	"kind" text NOT NULL,
	"ownership" text NOT NULL,
	"environment" text NOT NULL,
	"purchased_at" timestamp with time zone NOT NULL,
	"expires_at" timestamp with time zone,
	"revoked_at" timestamp with time zone,
	"in_trial" boolean DEFAULT false NOT NULL,
	"auto_renew" boolean,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "plus_purchases_pkey" PRIMARY KEY("original_transaction_id","user_id")
);
--> statement-breakpoint
CREATE INDEX "idx_plus_gifts_purchaser" ON "plus_gifts" USING btree ("purchaser_id");--> statement-breakpoint
CREATE INDEX "idx_plus_gifts_redeemed_by" ON "plus_gifts" USING btree ("redeemed_by");--> statement-breakpoint
CREATE INDEX "idx_plus_purchases_user" ON "plus_purchases" USING btree ("user_id");