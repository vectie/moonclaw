// See the Electron documentation for details on how to use preload scripts:
// https://www.electronjs.org/docs/latest/tutorial/process-model#preload-scripts

import { ElectronAPI } from "@moonclaw/core/lib/types.js";
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("electronAPI", {
  selectDirectory: () => ipcRenderer.invoke("select-directory"),
  getUrl: () => ipcRenderer.invoke("get-url"),
  moonclawReady: () => ipcRenderer.invoke("moonclaw-ready"),
  reloadApp: () => ipcRenderer.invoke("reload-app"),
  openPathInFileExplorer: (path: string) =>
    ipcRenderer.invoke("open-path-in-file-explorer", path),
} as ElectronAPI);
