const express = require("express");

const app = express();
const port = Number(process.env.PORT || 3000);

const version = process.env.APP_VERSION || "demo-v2";

app.get("/", (_req, res) => {
  res.json({
    application: "Deployment Automation Demo",
    version,
    status: "running",
    framework: "Node.js + Express"
  });
});

app.get("/health", (_req, res) => {
  res.status(200).json({
    status: "healthy",
    version
  });
});

app.listen(port, "127.0.0.1", () => {
  console.log(`Demo application listening on 127.0.0.1:${port}`);
});
