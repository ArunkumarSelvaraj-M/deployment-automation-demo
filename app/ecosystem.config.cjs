module.exports = {
  apps: [
    {
      name: "deployment-automation-demo",
      cwd: "/opt/deployment-demo/current/app",
      script: "server.js",
      interpreter: "node",
      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      watch: false,
      max_memory_restart: "300M",
      env: {
        NODE_ENV: "production",
        PORT: "3000",
        APP_VERSION: "demo-v2"
      }
    }
  ]
};
