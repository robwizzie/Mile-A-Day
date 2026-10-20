CREATE TABLE "coach_mcp_audit_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text,
	"grant_id" uuid,
	"tool" text NOT NULL,
	"args" jsonb,
	"outcome" text NOT NULL,
	"detail" text,
	"duration_ms" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "coach_mcp_audit_log" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "coach_mcp_oauth_clients" (
	"client_id" text PRIMARY KEY NOT NULL,
	"metadata" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "coach_mcp_oauth_clients" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "coach_mcp_oauth_codes" (
	"code_hash" text PRIMARY KEY NOT NULL,
	"client_id" text NOT NULL,
	"user_id" text NOT NULL,
	"redirect_uri" text NOT NULL,
	"code_challenge" text NOT NULL,
	"scope" text NOT NULL,
	"resource" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
ALTER TABLE "coach_mcp_oauth_codes" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "coach_mcp_oauth_grants" (
	"grant_id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"client_id" text NOT NULL,
	"scope" text NOT NULL,
	"resource" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"revoked_at" timestamp with time zone,
	"last_used_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "coach_mcp_oauth_grants" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "coach_mcp_oauth_requests" (
	"id" text PRIMARY KEY NOT NULL,
	"browser_key_hash" text NOT NULL,
	"client_id" text NOT NULL,
	"redirect_uri" text NOT NULL,
	"code_challenge" text NOT NULL,
	"state" text,
	"scope" text NOT NULL,
	"resource" text NOT NULL,
	"nonce" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
ALTER TABLE "coach_mcp_oauth_requests" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "coach_mcp_oauth_tokens" (
	"token_hash" text PRIMARY KEY NOT NULL,
	"grant_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"used_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "coach_mcp_oauth_tokens_kind_check" CHECK (kind IN ('access', 'refresh'))
);
--> statement-breakpoint
ALTER TABLE "coach_mcp_oauth_tokens" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "coach_mcp_oauth_grants" ADD CONSTRAINT "coach_mcp_oauth_grants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "coach_mcp_oauth_tokens" ADD CONSTRAINT "coach_mcp_oauth_tokens_grant_id_fkey" FOREIGN KEY ("grant_id") REFERENCES "public"."coach_mcp_oauth_grants"("grant_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_coach_mcp_audit_log_user_created" ON "coach_mcp_audit_log" USING btree ("user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "idx_coach_mcp_oauth_grants_user" ON "coach_mcp_oauth_grants" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_coach_mcp_oauth_tokens_grant" ON "coach_mcp_oauth_tokens" USING btree ("grant_id");