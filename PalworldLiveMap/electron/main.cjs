"use strict";

const { app, BrowserWindow, ipcMain } = require("electron");
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const readline = require("node:readline");

const RETRY_DELAY_MS = 2000;
let mainWindow = null;
let readerProcess = null;
let retryTimer = null;
let quitting = false;
let latestTelemetry = disconnected("reader-starting", "Starting local reader...");
let latestEntities = { schemaVersion: 1, type: "entities", items: [] };

function disconnected(status, message) {
  return {
    schemaVersion: 1,
    connected: false,
    status,
    message,
    world: "Palworld",
    sequence: 0,
    position: { x: null, y: null, z: null },
    rotation: { pitch: 0, yaw: 0, roll: 0 },
  };
}

function publishTelemetry(value) {
  latestTelemetry = value && typeof value === "object" ? value : disconnected("reader-error", "Invalid telemetry payload.");
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send("telemetry:update", latestTelemetry);
}

function publishEntities(value) {
  latestEntities = value && Array.isArray(value.items) ? value : { schemaVersion: 1, type: "entities", items: [] };
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send("entities:update", latestEntities);
}

function readerExecutable() {
  if (app.isPackaged) return path.join(process.resourcesPath, "reader", "PalworldLiveMap.Reader.exe");
  return path.join(__dirname, "..", "Reader", "bin", "Release", "net8.0-windows", "PalworldLiveMap.Reader.exe");
}

function scheduleReaderRestart() {
  if (quitting || retryTimer) return;
  retryTimer = setTimeout(() => {
    retryTimer = null;
    startReader();
  }, RETRY_DELAY_MS);
}

function startReader() {
  if (quitting || readerProcess) return;
  const executable = readerExecutable();
  if (!fs.existsSync(executable)) {
    publishTelemetry(disconnected("reader-not-built", "Build the external reader before starting Electron."));
    scheduleReaderRestart();
    return;
  }

  publishTelemetry(disconnected("reader-starting", "Connecting to Palworld..."));
  const child = spawn(executable, ["--json-lines", "--interval-ms=50", "--entity-scan-ms=2500"], {
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"],
  });
  readerProcess = child;

  const lines = readline.createInterface({ input: child.stdout, crlfDelay: Infinity });
  lines.on("line", (line) => {
    try {
      const payload = JSON.parse(line);
      if (payload.type === "entities") publishEntities(payload);
      else if (payload.type !== "entities-error") publishTelemetry(payload);
    } catch (_) {
      publishTelemetry(disconnected("reader-error", "The reader returned malformed telemetry."));
    }
  });
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (value) => {
    const message = value.trim();
    if (message) publishTelemetry(disconnected("reader-error", message.slice(0, 300)));
  });
  child.on("error", (error) => publishTelemetry(disconnected("reader-error", error.message)));
  child.on("exit", () => {
    lines.close();
    readerProcess = null;
    if (!quitting) {
      publishTelemetry(disconnected("waiting-for-palworld", "Start Palworld and enter a world."));
      scheduleReaderRestart();
    }
  });
}

function stopReader() {
  if (retryTimer) {
    clearTimeout(retryTimer);
    retryTimer = null;
  }
  if (readerProcess) {
    readerProcess.kill();
    readerProcess = null;
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 960,
    minHeight: 640,
    show: false,
    backgroundColor: "#091011",
    title: "Palworld Live Map",
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
    },
  });

  mainWindow.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (url !== mainWindow.webContents.getURL()) event.preventDefault();
  });
  mainWindow.once("ready-to-show", () => mainWindow.show());
  mainWindow.on("closed", () => { mainWindow = null; });
  mainWindow.loadFile(path.join(__dirname, "..", "App", "index.html"));
}

ipcMain.handle("telemetry:get", () => latestTelemetry);
ipcMain.handle("entities:get", () => latestEntities);
ipcMain.handle("actor:inspect", async (_event, id) => {
  if (typeof id !== "string" || !/^[0-9A-F]{8,16}$/i.test(id)) throw new Error("This pin does not have a live actor address.");
  return new Promise((resolve, reject) => {
    const child = spawn(readerExecutable(), [`--inspect-actor=${id}`], { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "", stderr = "";
    child.stdout.setEncoding("utf8"); child.stderr.setEncoding("utf8");
    child.stdout.on("data", (value) => { if (stdout.length < 4_000_000) stdout += value; });
    child.stderr.on("data", (value) => { if (stderr.length < 4000) stderr += value; });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code !== 0) { reject(new Error(stderr.trim() || "Actor inspection failed.")); return; }
      const line = stdout.split(/\r?\n/).find((value) => value.trim().startsWith("{") && value.includes('"type":"actor-inspection"'));
      if (!line) { reject(new Error("The actor disappeared before it could be inspected.")); return; }
      try { resolve(JSON.parse(line)); } catch (_) { reject(new Error("Actor inspection returned invalid data.")); }
    });
  });
});

app.whenReady().then(() => {
  createWindow();
  startReader();
  app.on("activate", () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on("before-quit", () => {
  quitting = true;
  stopReader();
});
app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
