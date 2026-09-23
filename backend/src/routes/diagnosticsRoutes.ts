import { Router } from "express";
import { recordMetricKitController } from "../controllers/diagnosticsController.js";

const router = Router();

// MetricKit crash/hang/metrics upload from the iOS app. Authenticated
// (mounted after authenticateToken in server.ts).
router.post("/metrickit", recordMetricKitController);

export default router;
