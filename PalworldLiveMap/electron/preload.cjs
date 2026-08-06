"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("palworldDesktop", Object.freeze({
  getTelemetry: () => ipcRenderer.invoke("telemetry:get"),
  onTelemetry: (callback) => {
    if (typeof callback !== "function") throw new TypeError("Telemetry callback must be a function.");
    const listener = (_event, telemetry) => callback(telemetry);
    ipcRenderer.on("telemetry:update", listener);
    return () => ipcRenderer.removeListener("telemetry:update", listener);
  },
  getEntities: () => ipcRenderer.invoke("entities:get"),
  inspectActor: (id) => ipcRenderer.invoke("actor:inspect", id),
  onEntities: (callback) => {
    if (typeof callback !== "function") throw new TypeError("Entities callback must be a function.");
    const listener = (_event, entities) => callback(entities);
    ipcRenderer.on("entities:update", listener);
    return () => ipcRenderer.removeListener("entities:update", listener);
  },
  platform: process.platform,
}));
