CREATE TABLE "client_diagnostics" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" varchar(255) NOT NULL,
	"client_id" varchar(64),
	"kind" varchar(32) NOT NULL,
	"app_version" varchar(32),
	"build" varchar(32),
	"os_version" varchar(64),
	"device_model" varchar(64),
	"signature" varchar(32) NOT NULL,
	"summary" varchar(300),
	"payload" jsonb NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	"occurred_at" timestamp with time zone
);
--> statement-breakpoint
CREATE INDEX "idx_client_diagnostics_kind_received" ON "client_diagnostics" USING btree ("kind","received_at");--> statement-breakpoint
CREATE INDEX "idx_client_diagnostics_signature" ON "client_diagnostics" USING btree ("signature","received_at" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_client_diagnostics_user_received" ON "client_diagnostics" USING btree ("user_id","received_at" DESC NULLS FIRST);--> statement-breakpoint
CREATE UNIQUE INDEX "uq_client_diagnostics_user_client" ON "client_diagnostics" USING btree ("user_id","client_id");