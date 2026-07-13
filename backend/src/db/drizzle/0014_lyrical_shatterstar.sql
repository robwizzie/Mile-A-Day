CREATE TABLE "android_waitlist" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"source" text DEFAULT 'website' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "android_waitlist_email_unique" UNIQUE("email")
);
