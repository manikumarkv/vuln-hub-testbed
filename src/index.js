// Minimal app so the Docker image has something to run.
// The dependencies are pinned to known-vulnerable versions on purpose (see README).
const express = require("express");
const _ = require("lodash");

const app = express();
app.get("/health", (_req, res) => res.json({ ok: true, lodash: _.VERSION }));
app.listen(process.env.PORT || 3000);
